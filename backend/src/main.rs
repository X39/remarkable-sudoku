//! Pen tool backend for the Sudoku app (reMarkable AppLoad).
//!
//! QML only sees the stylus as a plain mouse, so it cannot tell the pen tip from
//! the eraser end. The pen digitizer ("Elan marker input", an evdev device) does:
//! it reports BTN_TOOL_PEN or BTN_TOOL_RUBBER when an end of the stylus comes into
//! range. This backend watches those two codes and tells the UI which tool is active.
//!
//! AppLoad side (protocol from rm-appload, GPLv3; no code copied):
//!   argv[1] = path of a Unix SOCK_SEQPACKET socket; we connect to it.
//!   Every message = one packet {u32 type, u32 length} then, if length > 0,
//!   a second packet with the payload. 0xFFFFFFFE = new frontend,
//!   0xFFFFFFFF = terminate.
//!
//! Backend -> frontend types: 100 status text, 101 active tool ("pen" or "eraser"),
//! 102 contact started, payload = the tool that touched down,
//! 103 saved game (JSON text, empty when there is none), sent when a frontend connects.
//! UI -> backend: 200 save game (payload = JSON text), stored in SAVE_PATH.

use std::env;
use std::ffi::CString;
use std::fs;
use std::mem;
use std::process::exit;

const MSG_NEW_FRONTEND: u32 = 0xFFFF_FFFE;
const MSG_TERMINATE: u32 = 0xFFFF_FFFF;
const MAXP: usize = 4 * 1024 * 1024;
const SAVE_DIR: &str = "/home/root/.local/share/sudoku";
const SAVE_PATH: &str = "/home/root/.local/share/sudoku/save.json";
const FROM_UI_SAVE: u32 = 200;

const TO_UI_STATUS: u32 = 100;
const TO_UI_TOOL: u32 = 101;
const TO_UI_TOUCH: u32 = 102;
const TO_UI_STATE: u32 = 103;

const EV_KEY: u16 = 1;
const BTN_TOUCH: u16 = 0x14a;
const BTN_TOOL_PEN: u16 = 0x140;
const BTN_TOOL_RUBBER: u16 = 0x141;
const EVENT_SIZE: usize = 24; // aarch64 struct input_event: timeval (16) + type, code (2+2) + value (4)

struct AppLoad {
    fd: libc::c_int,
}

impl AppLoad {
    fn send_packet(&self, bytes: &[u8]) -> bool {
        // SAFETY: fd is a valid socket owned by this struct; bytes is a valid slice.
        let n = unsafe {
            libc::send(
                self.fd,
                bytes.as_ptr() as *const libc::c_void,
                bytes.len(),
                libc::MSG_NOSIGNAL,
            )
        };
        n >= 0
    }

    fn to_ui(&self, msg_type: u32, payload: &[u8]) {
        let mut header = [0u8; 8];
        header[..4].copy_from_slice(&msg_type.to_ne_bytes());
        header[4..].copy_from_slice(&(payload.len() as u32).to_ne_bytes());
        if self.send_packet(&header) && !payload.is_empty() {
            self.send_packet(payload);
        }
    }

    fn status(&self, text: &str) {
        self.to_ui(TO_UI_STATUS, text.as_bytes());
    }

    /// Receive one packet into `buf`. Returns the byte count, or None on error or EOF.
    fn recv_packet(&self, buf: &mut [u8]) -> Option<usize> {
        // SAFETY: buf is a valid writable slice of the given length.
        let n = unsafe {
            libc::recv(self.fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0)
        };
        if n < 1 { None } else { Some(n as usize) }
    }
}

fn open_socket(path: &str) -> Option<libc::c_int> {
    // SAFETY: plain libc socket/connect calls with a correctly built sockaddr_un.
    unsafe {
        let fd = libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0);
        if fd < 0 {
            return None;
        }
        let mut addr: libc::sockaddr_un = mem::zeroed();
        addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
        let bytes = path.as_bytes();
        let max = addr.sun_path.len() - 1;
        if bytes.len() > max {
            libc::close(fd);
            return None;
        }
        for (i, b) in bytes.iter().enumerate() {
            addr.sun_path[i] = *b as libc::c_char;
        }
        let len = mem::size_of::<libc::sockaddr_un>() as libc::socklen_t;
        if libc::connect(fd, &addr as *const _ as *const libc::sockaddr, len) != 0 {
            libc::close(fd);
            return None;
        }
        Some(fd)
    }
}

/// Finds /dev/input/eventN for the pen digitizer by name in /proc/bus/input/devices.
fn find_pen_device() -> Option<String> {
    let text = fs::read_to_string("/proc/bus/input/devices").ok()?;
    for block in text.split("\n\n") {
        if !block.contains("marker") {
            continue;
        }
        for line in block.lines() {
            if let Some(rest) = line.strip_prefix("H: Handlers=") {
                for token in rest.split_whitespace() {
                    if token.starts_with("event") {
                        return Some(format!("/dev/input/{token}"));
                    }
                }
            }
        }
    }
    None
}

fn open_device(path: &str) -> Option<libc::c_int> {
    let c = CString::new(path).ok()?;
    // SAFETY: c is a valid NUL-terminated path.
    let fd = unsafe { libc::open(c.as_ptr(), libc::O_RDONLY | libc::O_NONBLOCK | libc::O_CLOEXEC) };
    if fd < 0 { None } else { Some(fd) }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        exit(1);
    }
    let al_fd = match open_socket(&args[1]) {
        Some(fd) => fd,
        None => exit(2),
    };
    let al = AppLoad { fd: al_fd };
    // Big saved games: ask for a larger send buffer (root may exceed the usual cap).
    // SAFETY: plain setsockopt on our own socket with a valid int.
    unsafe {
        let size: libc::c_int = MAXP as libc::c_int;
        libc::setsockopt(al.fd, libc::SOL_SOCKET, libc::SO_SNDBUFFORCE,
            &size as *const _ as *const libc::c_void, mem::size_of::<libc::c_int>() as libc::socklen_t);
    }

    let mut dev_fd: libc::c_int = -1;
    let mut dev_note = String::from("pen device not found");
    if let Some(path) = find_pen_device() {
        match open_device(&path) {
            Some(fd) => {
                dev_fd = fd;
                dev_note = format!("watching {path}");
            }
            None => dev_note = format!("cannot open {path}"),
        }
    }

    let mut tool: &'static str = "pen";
    let mut buf = vec![0u8; MAXP + 1];
    let mut evbuf = [0u8; EVENT_SIZE * 64];

    loop {
        let mut fds = vec![libc::pollfd { fd: al.fd, events: libc::POLLIN, revents: 0 }];
        if dev_fd >= 0 {
            fds.push(libc::pollfd { fd: dev_fd, events: libc::POLLIN, revents: 0 });
        }
        // SAFETY: fds is a valid slice of pollfd structs.
        let r = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if r < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            break;
        }

        // Messages from the UI (AppLoad).
        if fds[0].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut header = [0u8; 8];
            if al.recv_packet(&mut header).map_or(true, |n| n < 8) {
                break;
            }
            let msg_type = u32::from_ne_bytes(header[..4].try_into().unwrap());
            let len = u32::from_ne_bytes(header[4..].try_into().unwrap()) as usize;
            if len > MAXP {
                break;
            }
            if len > 0 && al.recv_packet(&mut buf[..len]).is_none() {
                break;
            }
            if msg_type == MSG_TERMINATE {
                break;
            }
            if msg_type == MSG_NEW_FRONTEND {
                al.status(&dev_note);
                al.to_ui(TO_UI_TOOL, tool.as_bytes());
                let saved = fs::read(SAVE_PATH).unwrap_or_default();
                al.to_ui(TO_UI_STATE, &saved);
            } else if msg_type == FROM_UI_SAVE && len > 0 {
                // write to a temp file first so a crash never leaves a half-written save
                let tmp = format!("{SAVE_PATH}.tmp");
                let _ = fs::create_dir_all(SAVE_DIR);
                if fs::write(&tmp, &buf[..len]).is_ok() {
                    let _ = fs::rename(&tmp, SAVE_PATH);
                }
            }
        }

        // Events from the pen digitizer.
        if fds.len() > 1 && fds[1].revents & (libc::POLLIN | libc::POLLHUP | libc::POLLERR) != 0 {
            // SAFETY: evbuf is a valid writable buffer of the given length.
            let n = unsafe {
                libc::read(dev_fd, evbuf.as_mut_ptr() as *mut libc::c_void, evbuf.len())
            };
            if n < 0 {
                if std::io::Error::last_os_error().raw_os_error() == Some(libc::EAGAIN) {
                    continue;
                }
                al.status("pen device read failed");
                // SAFETY: closing the fd we opened.
                unsafe { libc::close(dev_fd) };
                dev_fd = -1;
                continue;
            }
            let count = n as usize / EVENT_SIZE;
            for i in 0..count {
                let e = &evbuf[i * EVENT_SIZE..(i + 1) * EVENT_SIZE];
                let ev_type = u16::from_ne_bytes(e[16..18].try_into().unwrap());
                let code = u16::from_ne_bytes(e[18..20].try_into().unwrap());
                let value = i32::from_ne_bytes(e[20..24].try_into().unwrap());
                if ev_type != EV_KEY {
                    continue;
                }
                // Contact: tell the UI which tool touched down. The kernel reports the tool
                // in range before contact, so this is always right, even if the UI has not
                // processed the earlier tool-change message yet.
                if code == BTN_TOUCH && value == 1 {
                    al.to_ui(TO_UI_TOUCH, tool.as_bytes());
                    continue;
                }
                let new_tool = match (code, value) {
                    (BTN_TOOL_RUBBER, 1) => Some("eraser"),
                    (BTN_TOOL_PEN, 1) => Some("pen"),
                    (BTN_TOOL_RUBBER, 0) if tool == "eraser" => Some("pen"),
                    _ => None,
                };
                if let Some(t) = new_tool {
                    if t != tool {
                        tool = t;
                        al.to_ui(TO_UI_TOOL, tool.as_bytes());
                    }
                }
            }
        }
    }

    // SAFETY: closing the fds we opened.
    unsafe {
        if dev_fd >= 0 {
            libc::close(dev_fd);
        }
        libc::close(al.fd);
    }
}
