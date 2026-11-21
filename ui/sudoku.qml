import QtQuick 2.15   // component/function syntax; fine on Qt 5.15 and Qt 6
import QtQuick.Controls 2.5
import net.asivery.ApploadUtils
import net.asivery.AppLoad 1.0
import "digit-recognizer.js" as Recognizer

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    // Whole-screen refresh area. DisplayMethodArea has no Full mode on this firmware;
    // the modes are UFast, Fast, Content and UI.
    DisplayMethodArea {
        anchors.fill: parent
        displayMethod: DisplayMethodArea.Content
    }

    signal close
    function unloading() {
        console.log("Sudoku unloading");
        if (gameReady) { flushLive(); saveNow(); }
        endpoint.terminate();
    }

    // design tokens
    readonly property color ink: "#161616"
    readonly property color mute: "#7a7a7a"
    readonly property color hair: "#d4d4d4"
    readonly property color accent: "#1f4fd8"
    readonly property color accentTint: "#e8eefc"

    // rotated rounded bar centred at (cx, cy); building block of the pictograms
    component Bar: Rectangle {
        property real cx: 28
        property real cy: 28
        property real len: 30
        property real ang: 0
        property color c: root.ink
        width: len; height: 6; radius: 3; color: c
        x: cx - len / 2; y: cy - 3; rotation: ang
    }

    // pictograms built from plain rectangles (no icon font on the tablet)
    component Ico: Item {
        id: ic
        property string kind: ""
        property color c: root.ink
        property color bg: root.tileBg
        width: 56; height: 56
        // arrow (undo / redo)
        Item { anchors.fill: parent; visible: ic.kind === "undo" || ic.kind === "redo"
            scale: ic.kind === "redo" ? -1 : 1
            Bar { c: ic.c; cx: 30; cy: 28; len: 34 }
            Bar { c: ic.c; cx: 17; cy: 21; len: 20; ang: -45 }
            Bar { c: ic.c; cx: 17; cy: 35; len: 20; ang: 45 }
        }
        // check mark
        Item { anchors.fill: parent; visible: ic.kind === "check"
            Bar { c: ic.c; cx: 17; cy: 32; len: 18; ang: 45 }
            Bar { c: ic.c; cx: 32; cy: 27; len: 34; ang: -50 }
        }
        // ghost
        Item { anchors.fill: parent; visible: ic.kind === "ghost"
            Rectangle { x: 10; y: 6; width: 36; height: 44; radius: 18; color: ic.c }
            Rectangle { x: 10; y: 30; width: 36; height: 20; color: ic.c }
            Rectangle { x: 19; y: 20; width: 7; height: 9; radius: 3.5; color: ic.bg }
            Rectangle { x: 31; y: 20; width: 7; height: 9; radius: 3.5; color: ic.bg }
        }
        // plus
        Item { anchors.fill: parent; visible: ic.kind === "plus"
            Bar { c: ic.c; cx: 28; cy: 28; len: 36 }
            Bar { c: ic.c; cx: 28; cy: 28; len: 36; ang: 90 }
        }
        // restart (ring with a gap and an arrow head)
        Item { anchors.fill: parent; visible: ic.kind === "restart"
            Rectangle { x: 8; y: 8; width: 40; height: 40; radius: 20; color: "transparent"; border.width: 6; border.color: ic.c }
            Rectangle { x: 28; y: 2; width: 24; height: 18; color: ic.bg }
            Bar { c: ic.c; cx: 38; cy: 12; len: 18; ang: 0 }
            Bar { c: ic.c; cx: 44; cy: 18; len: 16; ang: 90 }
        }
        // refresh (four corner brackets)
        Item { anchors.fill: parent; visible: ic.kind === "refresh"
            Bar { c: ic.c; cx: 14; cy: 8; len: 14 }  Bar { c: ic.c; cx: 8; cy: 14; len: 14; ang: 90 }
            Bar { c: ic.c; cx: 42; cy: 8; len: 14 }  Bar { c: ic.c; cx: 48; cy: 14; len: 14; ang: 90 }
            Bar { c: ic.c; cx: 14; cy: 48; len: 14 } Bar { c: ic.c; cx: 8; cy: 42; len: 14; ang: 90 }
            Bar { c: ic.c; cx: 42; cy: 48; len: 14 } Bar { c: ic.c; cx: 48; cy: 42; len: 14; ang: 90 }
            Rectangle { x: 22; y: 22; width: 12; height: 12; radius: 6; color: ic.c }
        }
        // close (cross)
        Item { anchors.fill: parent; visible: ic.kind === "close"
            Bar { c: ic.c; cx: 28; cy: 28; len: 38; ang: 45 }
            Bar { c: ic.c; cx: 28; cy: 28; len: 38; ang: -45 }
        }
    }
    readonly property color tileBg: "#f1f1f1"

    // soft tile button. kind: "soft" (default), "solid" (primary). `active` fills with activeColor;
    // `dim` greys it out. With `icon` set it is a vertical tile: pictogram above label.
    component Btn: Rectangle {
        id: bt
        property string label: ""
        property string icon: ""
        property string kind: "soft"
        property bool active: false
        property bool dim: false
        property int fontPx: 30
        signal clicked
        property color activeColor: root.ink
        readonly property bool filled: active || kind === "solid"
        readonly property color fg: filled ? "white" : (dim ? "#b0b0b0" : root.ink)
        radius: 30
        color: filled ? (ma.pressed ? Qt.lighter(activeColor, 1.6) : activeColor)
                      : (ma.pressed ? "#dcdcdc" : root.tileBg)
        Column {
            anchors.centerIn: parent
            spacing: 10
            Ico {
                id: pic
                anchors.horizontalCenter: parent.horizontalCenter
                visible: bt.icon !== ""
                kind: bt.icon
                c: bt.fg
                bg: bt.color
            }
            Text {
                width: bt.width - 16
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: bt.label
                font.pixelSize: bt.fontPx
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
                color: bt.fg
            }
        }
        MouseArea { id: ma; anchors.fill: parent; onClicked: bt.clicked() }
    }

    // pill switch row for the options panel
    component Toggle: Item {
        id: tg
        property string label: ""
        property string hint: ""
        property bool on: false
        signal toggled
        height: 120
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: root.hair }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            spacing: 4
            Text { text: tg.label; font.pixelSize: 34; font.weight: Font.Medium; color: root.ink }
            Text { text: tg.hint; font.pixelSize: 25; color: root.mute; visible: tg.hint !== "" }
        }
        Rectangle {
            id: track
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 112; height: 60; radius: 30
            color: tg.on ? root.accent : "white"
            border.width: 2
            border.color: tg.on ? root.accent : root.ink
            Rectangle {
                width: 44; height: 44; radius: 22
                y: 8
                x: tg.on ? parent.width - width - 8 : 8
                color: tg.on ? "white" : root.ink
            }
        }
        MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
    }

    // ---- pen tool from the backend ----
    // The backend reads the pen digitizer and reports which end of the stylus is in
    // range (QML only sees the stylus as a plain mouse). 101 = "pen" | "eraser".
    property string penTool: "pen"
    property bool erasing: false
    AppLoad {
        id: endpoint
        applicationID: "sudoku"
        onMessageReceived: (type, contents) => {
            if (type === 101) {
                root.penTool = contents;
            } else if (type === 102) {
                // contact started: this is the tool that actually touched down
                root.penTool = contents;
                root.lastTouchMsgMs = Date.now();
                if (root.pressPending) root.flushPress();
            } else if (type === 103) {
                root.loadSaved(contents);
            }
        }
    }

    // A pen press waits briefly for the backend's touch-down message so the first
    // points are never handled with a stale tool. Finger presses (src 2) do not wait.
    property bool pressPending: false
    property var pendingPts: []
    property real lastTouchMsgMs: 0
    function penPress(x, y, src) {
        if (src !== 0 || Date.now() - lastTouchMsgMs < 150) {
            beginStroke(x, y);   // finger, or the touch-down message already arrived
            return;
        }
        pressPending = true;
        pendingPts = [{x: x, y: y}];
        decideTimer.restart();
    }
    function penMove(x, y) {
        if (pressPending) { pendingPts.push({x: x, y: y}); return; }
        addPoint(x, y);
    }
    function penRelease() {
        if (pressPending) flushPress();
        endStroke();
    }
    function flushPress() {
        decideTimer.stop();
        pressPending = false;
        var pts = pendingPts;
        pendingPts = [];
        if (pts.length === 0) return;
        beginStroke(pts[0].x, pts[0].y);
        for (var i = 1; i < pts.length; i++) addPoint(pts[i].x, pts[i].y);
    }
    Timer {
        id: decideTimer
        interval: 80      // fallback if no touch-down message arrives (e.g. backend not running)
        repeat: false
        onTriggered: root.flushPress()
    }

    // ---- game state ----
    property var cells: []       // current values, 0 = empty
    property var givens: []      // true if fixed
    property var solution: []    // solved grid
    property var wrong: []       // marked wrong by Check
    property int rev: 0          // bump to refresh every binding
    property bool solved: false
    property string message: ""

    // ---- options (the New game panel) ----
    property int givensTarget: 40          // clues in a new puzzle: fewer = harder
    property bool liveErrors: false        // tint conflicting cells as soon as they appear
    property bool refreshAfterWrite: true  // black flash over changed cells to clear ghosting
    property bool ghostMode: false         // tapping a cell's small numbers switches candidates on/off
    property var ghosts: []                // per cell: bitmask of switched-on candidates (bit 0 = digit 1)
    property bool inkLive: false           // live (uncommitted) ink is on screen
    function setGhost(c, mask) {
        var g = ghosts.slice();
        g[c] = mask;
        ghosts = g;
    }

    // ---- puzzle logic ----
    function peersMask(b, i) {
        var r = Math.floor(i / 9), c = i % 9;
        var br = r - r % 3, bc = c - c % 3;
        var mask = 0;
        for (var k = 0; k < 9; k++) {
            mask |= 1 << b[r * 9 + k];
            mask |= 1 << b[k * 9 + c];
            mask |= 1 << b[(br + Math.floor(k / 3)) * 9 + bc + k % 3];
        }
        return mask;   // bit 0 is for empty cells, ignored by callers
    }

    function shuffled(arr) {
        for (var i = arr.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var t = arr[i]; arr[i] = arr[j]; arr[j] = t;
        }
        return arr;
    }

    // Finds the empty cell with fewest candidates. Returns -1 when full, -2 on dead end.
    function pickCell(b) {
        var best = -1, bestCount = 10;
        for (var i = 0; i < 81; i++) {
            if (b[i] !== 0) continue;
            var m = peersMask(b, i), n = 0;
            for (var d = 1; d <= 9; d++) if (!(m & (1 << d))) n++;
            if (n === 0) return -2;
            if (n < bestCount) { bestCount = n; best = i; if (n === 1) break; }
        }
        return best;
    }

    // Counts solutions, stopping at limit.
    function countSolutions(b, limit) {
        var i = pickCell(b);
        if (i === -2) return 0;
        if (i === -1) return 1;
        var m = peersMask(b, i), total = 0;
        for (var d = 1; d <= 9; d++) {
            if (m & (1 << d)) continue;
            b[i] = d;
            total += countSolutions(b, limit - total);
            b[i] = 0;
            if (total >= limit) break;
        }
        return total;
    }

    // Fills b completely with a random valid solution. Returns true on success.
    function fillRandom(b) {
        var i = pickCell(b);
        if (i === -2) return false;
        if (i === -1) return true;
        var m = peersMask(b, i);
        var digits = shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9]);
        for (var k = 0; k < 9; k++) {
            var d = digits[k];
            if (m & (1 << d)) continue;
            b[i] = d;
            if (fillRandom(b)) return true;
            b[i] = 0;
        }
        return false;
    }

    function newGame(targetGivens) {
        clearAllInk();
        var full = [];
        for (var i = 0; i < 81; i++) full.push(0);
        fillRandom(full);
        var puzzle = full.slice();
        var order = [];
        for (var j = 0; j < 81; j++) order.push(j);
        shuffled(order);
        var givenCount = 81;
        for (var n = 0; n < 81 && givenCount > targetGivens; n++) {
            var idx = order[n];
            var saved = puzzle[idx];
            puzzle[idx] = 0;
            var probe = puzzle.slice();
            if (countSolutions(probe, 2) !== 1) {
                puzzle[idx] = saved;   // removal breaks uniqueness, keep it
            } else {
                givenCount--;
            }
        }
        var g = [], w = [];
        for (var q = 0; q < 81; q++) { g.push(puzzle[q] !== 0); w.push(false); }
        solution = full;
        cells = puzzle;
        givens = g;
        wrong = w;
        solved = false;
        undoStack = [];
        redoStack = [];
        histRev++;
        message = givenCount + " clues. Write digits with the pen; erase with its other end.";
        rev++;
        flashAll();
    }

    function isConflict(i) {
        var v = cells[i];
        if (v === 0) return false;
        var r = Math.floor(i / 9), c = i % 9;
        var br = r - r % 3, bc = c - c % 3;
        for (var k = 0; k < 9; k++) {
            var a = r * 9 + k, b2 = k * 9 + c;
            var d = (br + Math.floor(k / 3)) * 9 + bc + k % 3;
            if (a !== i && cells[a] === v) return true;
            if (b2 !== i && cells[b2] === v) return true;
            if (d !== i && cells[d] === v) return true;
        }
        return false;
    }

    // true when digit d written into cell would clash with another cell in its row, column or box
    function clashes(cell, d) {
        var r = Math.floor(cell / 9), c = cell % 9;
        var br = r - r % 3, bc = c - c % 3;
        for (var k = 0; k < 9; k++) {
            var a = r * 9 + k, b2 = k * 9 + c;
            var e = (br + Math.floor(k / 3)) * 9 + bc + k % 3;
            if (a !== cell && cells[a] === d) return true;
            if (b2 !== cell && cells[b2] === d) return true;
            if (e !== cell && cells[e] === d) return true;
        }
        return false;
    }

    // reads below tieSure confidence are decided by the sudoku rules among candidates >= tieFloor
    readonly property real tieSure: 0.80
    readonly property real tieFloor: 0.15
    function readCell(res, cell) {
        if (res.confidence < 0.5) return res;
        var p = Recognizer.pickDigit(res, function (d) { return clashes(cell, d); }, tieSure, tieFloor);
        if (p.tie) console.log("DBG tiebreak cell " + cell + ": best " + res.digit + " (" + Math.round(res.confidence * 100) + "%) -> " + p.digit + " (" + Math.round(p.confidence * 100) + "%)");
        return {digit: p.digit, confidence: p.confidence, scores: res.scores, tie: p.tie, best: res.digit};
    }

    function boardComplete() {
        for (var i = 0; i < 81; i++) {
            if (cells[i] === 0 || isConflict(i)) return false;
        }
        return true;
    }

    function updateSolved() {
        solved = boardComplete();
        if (solved) message = "Solved!";
    }

    // sets only the value of a cell (ink and history are handled by the callers)
    function setValueOnly(i, v) {
        var c = cells.slice();
        c[i] = v;
        cells = c;
        var w = wrong.slice();
        w[i] = false;
        wrong = w;
    }

    function checkBoard() {
        flushLive();
        if (cells.length === 0) return;
        if (solved || boardComplete()) {
            solved = true;
            message = "Solved!";
            rev++;
            if (refreshAfterWrite) flashAll();
            return;
        }
        var w = [], bad = 0, empty = 0;
        for (var i = 0; i < 81; i++) {
            var isBad = cells[i] !== 0 && cells[i] !== solution[i];
            w.push(isBad);
            if (isBad) bad++;
            if (cells[i] === 0) empty++;
        }
        wrong = w;
        if (bad > 0) message = bad + " wrong entr" + (bad === 1 ? "y" : "ies") + " marked with X.";
        else message = "No mistakes so far, " + empty + " cells left.";
        rev++;
        if (refreshAfterWrite) flashAll();
    }

    // ---- ink store: committed handwriting, per cell ----
    // inkStore[cell] = [stroke...]; a stroke is an array of {x, y} in grid pixels, already
    // smoothed and densified (a point every ~2.5 px) so the eraser can cut it anywhere.
    // Strokes are never changed after they are stored (the eraser builds new ones), so
    // snapshots can share them.
    property var inkStore: []

    function emptyStore() {
        var st = [];
        for (var i = 0; i < 81; i++) st.push([]);
        return st;
    }

    // adds points so no gap between neighbours is longer than step
    function densify(pts, step) {
        if (pts.length < 2) return pts;
        var out = [pts[0]];
        for (var i = 1; i < pts.length; i++) {
            var a = pts[i - 1], b = pts[i];
            var dx = b.x - a.x, dy = b.y - a.y;
            var n = Math.ceil(Math.sqrt(dx * dx + dy * dy) / step);
            for (var t = 1; t < n; t++) out.push({x: a.x + dx * t / n, y: a.y + dy * t / n});
            out.push(b);
        }
        return out;
    }

    function boundsOf(list) {
        if (list.length === 0) return null;
        var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
        for (var i = 0; i < list.length; i++) {
            for (var k = 0; k < list[i].length; k++) {
                var p = list[i][k];
                if (p.x < minX) minX = p.x;
                if (p.x > maxX) maxX = p.x;
                if (p.y < minY) minY = p.y;
                if (p.y > maxY) maxY = p.y;
            }
        }
        return {minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                size: Math.max(maxX - minX, maxY - minY)};
    }

    // the rubber: cuts every stroke point inside the disc out of the strokes. Returns the
    // new stroke list, or null if the disc touched nothing.
    function cutStrokes(list, x, y, r) {
        var r2 = r * r, out = [], changed = false;
        for (var s = 0; s < list.length; s++) {
            var st = list[s], run = [], hit = false;
            for (var k = 0; k < st.length; k++) {
                var dx = st[k].x - x, dy = st[k].y - y;
                if (dx * dx + dy * dy <= r2) {
                    hit = true;
                    if (run.length >= 2) out.push(run);
                    run = [];
                } else {
                    run.push(st[k]);
                }
            }
            if (!hit) { out.push(st); continue; }
            changed = true;
            if (run.length >= 2) out.push(run);
        }
        return changed ? out : null;
    }

    function repaintInk(c) {
        var cv = inkCanvases.itemAt(c);
        if (cv) cv.requestPaint();
    }

    // 1-2-1 smoothing of a stroke's points (end points stay), two passes (done once, at commit)
    function smoothPoints(pts) {
        var p = pts;
        for (var pass = 0; pass < 2; pass++) {
            if (p.length < 3) break;
            var q = [p[0]];
            for (var i = 1; i < p.length - 1; i++) {
                q.push({x: (p[i - 1].x + 2 * p[i].x + p[i + 1].x) / 4,
                        y: (p[i - 1].y + 2 * p[i].y + p[i + 1].y) / 4});
            }
            q.push(p[p.length - 1]);
            p = q;
        }
        return p;
    }

    // draws one stroke as a smooth line (quadratic curves through the mid points)
    function drawStroke(ctx, pts, ox, oy) {
        var p = pts;
        ctx.beginPath();
        if (p.length === 1) {
            ctx.arc(p[0].x - ox, p[0].y - oy, ctx.lineWidth / 2, 0, 2 * Math.PI);
            ctx.fill();
            return;
        }
        ctx.moveTo(p[0].x - ox, p[0].y - oy);
        for (var i = 1; i < p.length - 1; i++) {
            var mx = (p[i].x + p[i + 1].x) / 2 - ox, my = (p[i].y + p[i + 1].y) / 2 - oy;
            ctx.quadraticCurveTo(p[i].x - ox, p[i].y - oy, mx, my);
        }
        ctx.lineTo(p[p.length - 1].x - ox, p[p.length - 1].y - oy);
        ctx.stroke();
    }

    function paintCellInk(ctx, i, ox, oy) {
        var s = inkStore[i];
        if (!s) return;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.lineWidth = Math.max(3, grid.cell * 0.05);
        ctx.strokeStyle = "black";
        ctx.fillStyle = "black";
        for (var a = 0; a < s.length; a++) drawStroke(ctx, s[a], ox, oy);
    }

    // ---- history (undo / redo) ----
    property var undoStack: []
    property var redoStack: []
    property int histRev: 0
    readonly property bool canUndo: histRev >= 0 && undoStack.length > 0
    readonly property bool canRedo: histRev >= 0 && redoStack.length > 0

    function snap(c) {
        return {value: cells[c], ink: inkStore[c].slice(), ghost: ghosts[c]};
    }
    function applySnap(c, s) {
        setValueOnly(c, s.value);
        inkStore[c] = s.ink.slice();
        setGhost(c, s.ghost);
        repaintInk(c);
    }
    // changes: [{c, before, after}] recorded as ONE undo step
    function recordAction(changes) {
        if (changes.length === 0) return;
        undoStack.push({changes: changes});
        if (undoStack.length > 300) undoStack.shift();
        redoStack = [];
        histRev++;
    }
    function recordChange(c, before) {
        recordAction([{c: c, before: before, after: snap(c)}]);
    }
    function afterHistoryStep(a, text) {
        for (var i = 0; i < a.changes.length; i++) {
            if (refreshAfterWrite) flashCell(a.changes[i].c);
        }
        solved = false;
        message = text;
        updateSolved();
        histRev++;
        rev++;
    }
    function undo() {
        flushLive();
        if (undoStack.length === 0) return;
        var a = undoStack.pop();
        for (var i = a.changes.length - 1; i >= 0; i--) applySnap(a.changes[i].c, a.changes[i].before);
        redoStack.push(a);
        afterHistoryStep(a, "Undone.");
    }
    function redo() {
        flushLive();
        if (redoStack.length === 0) return;
        var a = redoStack.pop();
        for (var i = 0; i < a.changes.length; i++) applySnap(a.changes[i].c, a.changes[i].after);
        undoStack.push(a);
        afterHistoryStep(a, "Redone.");
    }
    // wipes all own entries and notes (one undo step)
    function restartPuzzle() {
        flushLive();
        var ch = [];
        for (var c = 0; c < 81; c++) {
            if (givens[c]) continue;
            if (cells[c] !== 0 || inkStore[c].length > 0 || ghosts[c] !== 0) {
                var before = snap(c);
                setValueOnly(c, 0);
                inkStore[c] = [];
                setGhost(c, 0);
                repaintInk(c);
                ch.push({c: c, before: before, after: snap(c)});
            }
        }
        var w = [];
        for (var q = 0; q < 81; q++) w.push(false);
        wrong = w;
        recordAction(ch);
        solved = false;
        message = ch.length > 0 ? "Restarted. Undo brings your entries back." : "Nothing to clear.";
        rev++;
        if (refreshAfterWrite) flashAll();
    }

    // ---- clean refresh ----
    // xochitl's own anti-ghosting (what a notebook open and AppLoad's 5-finger gesture run):
    // `ghostBuster` is an id in xochitl's QML that apps can see by name. It clears the whole
    // panel and is noticeable, so it runs only (a) when the refresh button is tapped and
    // (b) after the board has changed and then sat idle for idleClearMs.
    readonly property int idleClearMs: 30000
    function flashRect(x, y, w, h) { idleClearTimer.restart(); }   // something changed: clear when idle
    function ghostClear() { idleClearTimer.stop(); ghostTimer.restart(); }
    Timer {
        id: idleClearTimer
        interval: root.idleClearMs
        repeat: false
        onTriggered: {
            if (root.inkLive || root.pressPending || root.erasing) { restart(); return; }
            root.ghostClear();
        }
    }
    Timer {
        id: ghostTimer
        interval: 200   // the new content is on screen first
        repeat: false
        onTriggered: {
            try { ghostBuster.forceClearNow("sudoku"); }
            catch (e) { console.log("DBG ghostBuster unavailable: " + e); }
        }
    }
    function flashCell(i) {
        flashRect((i % 9) * grid.cell, Math.floor(i / 9) * grid.cell, grid.cell, grid.cell);
    }
    function flashAll() {   // immediate, for whole-board changes (new game, undo all, restart)
        idleClearTimer.restart();
    }
    // flash the area a piece of ink covered
    function flashInk(b) {
        var x0 = Math.max(0, b.minX - 14), y0 = Math.max(0, b.minY - 14);
        var x1 = Math.min(grid.width, b.maxX + 14), y1 = Math.min(grid.height, b.maxY + 14);
        flashRect(x0, y0, x1 - x0, y1 - y0);
    }

    // ---- view switch (New game panel) with a full black flash, like Minesweeper ----
    property bool panelOpen: false
    property bool flashing: false
    property string pendingAction: ""
    function requestPanel(action) {   // "open" | "close" | "start" | "refresh"
        if (flashing) return;
        flushLive();
        pendingAction = action;
        flashing = true;
        screenFlashTimer.interval = action === "refresh" ? 400 : 120;   // longer black = cleaner panel
        screenFlashTimer.start();
    }
    Timer {
        id: screenFlashTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (root.pendingAction === "open") {
                root.panelOpen = true;
            } else if (root.pendingAction === "close") {
                root.panelOpen = false;
                root.ghostClear();   // leaving the New game panel: same full clear as the refresh button
            } else if (root.pendingAction === "start") {
                root.panelOpen = false;
                root.newGame(root.givensTarget);
                root.ghostClear();
            }
            root.pendingAction = "";
            root.flashing = false;
        }
    }

    // ---- saved session ----
    // The backend keeps one JSON save file. The game is saved when the close button is
    // tapped (and when the app unloads); it is restored at start.
    // Undo history is not saved.
    property bool gameReady: false
    function packInk() {
        var out = {};
        for (var c = 0; c < 81; c++) {
            var st = inkStore[c];
            if (!st || st.length === 0) continue;
            var strokes = [];
            for (var a = 0; a < st.length; a++) {
                var pts = st[a], flat = [], lx = -99, ly = -99;
                for (var i = 0; i < pts.length; i++) {
                    var x = Math.round(pts[i].x), y = Math.round(pts[i].y);
                    var last = (i === pts.length - 1);
                    if (!last && i > 0 && Math.abs(x - lx) + Math.abs(y - ly) < 4) continue;
                    flat.push(x, y); lx = x; ly = y;
                }
                strokes.push(flat);
            }
            out[c] = strokes;
        }
        return out;
    }
    function saveNow() {
        if (!gameReady) return;
        var g = "";
        for (var i = 0; i < 81; i++) g += givens[i] ? "1" : "0";
        var state = {v: 1, cells: cells, givens: g, solution: solution, ghosts: ghosts,
                     ink: packInk(), solved: solved, message: message,
                     givensTarget: givensTarget, liveErrors: liveErrors,
                     refreshAfterWrite: refreshAfterWrite};
        endpoint.sendMessage(200, JSON.stringify(state));
    }
    function loadSaved(text) {
        if (gameReady) return;
        var st = null;
        try { st = text ? JSON.parse(text) : null; } catch (e) { st = null; }
        if (!st || st.v !== 1 || !st.cells || st.cells.length !== 81 || !st.solution || st.solution.length !== 81) {
            startFresh();
            return;
        }
        startupTimer.stop();
        clearAllInk();
        var gv = [], wr = [];
        for (var i = 0; i < 81; i++) { gv.push(st.givens.charAt(i) === "1"); wr.push(false); }
        var store = emptyStore();
        for (var key in st.ink) {
            var strokes = st.ink[key], list = [];
            for (var a = 0; a < strokes.length; a++) {
                var f = strokes[a], pts = [];
                for (var k = 0; k + 1 < f.length; k += 2) pts.push({x: f[k], y: f[k + 1]});
                list.push(pts);
            }
            store[Number(key)] = list;
        }
        inkStore = store;
        solution = st.solution;
        cells = st.cells;
        givens = gv;
        wrong = wr;
        ghosts = st.ghosts && st.ghosts.length === 81 ? st.ghosts : ghosts;
        givensTarget = st.givensTarget || givensTarget;
        liveErrors = !!st.liveErrors;
        refreshAfterWrite = st.refreshAfterWrite !== false;
        undoStack = []; redoStack = []; histRev++;
        solved = !!st.solved;
        message = st.message || "";
        gameReady = true;
        for (var c = 0; c < 81; c++) repaintInk(c);
        rev++;
        flashModel.clear();
    }
    function startFresh() {
        if (gameReady) return;
        startupTimer.stop();
        newGame(givensTarget);
        flashModel.clear();   // no black flash on first load; the board is fresh anyway
        gameReady = true;
    }
    // no backend answer (e.g. backend not running): start a new game after a short wait
    Timer { id: startupTimer; interval: 1500; running: true; onTriggered: root.startFresh() }
    // build time written by tools/build.sh; logged (not shown) so a stale build can be
    // spotted in the journal: journalctl | grep "DBG build"
    Component.onCompleted: {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE) console.log("DBG build " + x.responseText.trim());
        };
        x.open("GET", Qt.resolvedUrl("build-stamp.txt"));
        x.send();
    }

    // ---- title and status ----
    Rectangle { anchors.verticalCenter: title.verticalCenter; x: 150; width: title.x - 150 - 28; height: 2; color: root.hair }
    Rectangle { anchors.verticalCenter: title.verticalCenter; x: title.x + title.width + 28; width: root.width - x - 150; height: 2; color: root.hair }
    // whole-page refresh: round button in the opposite corner
    Rectangle {
        id: refreshBtn
        width: 92; height: 92; radius: 46
        anchors.verticalCenter: title.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 40
        color: refreshMa.pressed ? "#dcdcdc" : root.tileBg
        Ico { anchors.centerIn: parent; kind: "refresh"; bg: refreshBtn.color }
        MouseArea { id: refreshMa; anchors.fill: parent; anchors.margins: -10; onClicked: { root.flushLive(); root.ghostClear(); } }
    }
    // close: round button in the corner, where an app's close control is expected
    Rectangle {
        id: closeBtn
        width: 92; height: 92; radius: 46
        anchors.verticalCenter: title.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 40
        color: closeMa.pressed ? "#dcdcdc" : root.tileBg
        Ico { anchors.centerIn: parent; kind: "close"; bg: closeBtn.color }
        MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -10; onClicked: { root.flushLive(); root.saveNow(); root.close(); } }
    }
    Text {
        id: title
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        text: "SUDOKU"
        font.pixelSize: 54
        font.weight: Font.Bold
        font.letterSpacing: 12
        color: root.ink
    }

    Rectangle {
        anchors.centerIn: status
        visible: root.ghostMode || root.solved
        width: Math.min(status.width, statusText.contentWidth + 64)
        height: 54
        radius: 27
        color: root.ghostMode ? root.accentTint : "#e3f2e3"
    }
    Item {
        id: status
        anchors.top: title.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 120
        height: 54
        Text {
            id: statusText
            anchors.centerIn: parent
            width: parent.width - 48
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.ghostMode ? "Ghost mode: tap small numbers to toggle" : root.message
            elide: Text.ElideRight
            font.pixelSize: root.solved ? 38 : 30
            font.weight: (root.solved || root.ghostMode) ? Font.DemiBold : Font.Normal
            color: root.ghostMode ? root.accent : (root.solved ? "#1d6b1d" : root.mute)
        }
    }

    // ---- grid ----
    Item {
        id: grid
        anchors.top: status.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        // as large as the screen allows; two rows of buttons sit below the grid
        property real cell: Math.max(70, Math.min(Math.floor((root.width - 80) / 9), Math.floor((root.height - 470) / 9)))
        width: cell * 9
        height: cell * 9

        Repeater {
            model: 81
            delegate: Rectangle {
                id: cellRect
                property int idx: index
                // reading rev makes these re-evaluate after every state change
                property int value: root.rev >= 0 ? (root.cells[idx] || 0) : 0
                property bool isGiven: root.rev >= 0 && root.givens[idx] === true
                // errors show only after Check, or live if the option is on
                property bool isWrong: root.rev >= 0 && root.wrong[idx] === true
                property bool isLiveError: root.rev >= 0 && root.liveErrors && root.isConflict(idx)

                x: (idx % 9) * grid.cell
                y: Math.floor(idx / 9) * grid.cell
                width: grid.cell
                height: grid.cell
                color: (isWrong || isLiveError) ? "#f0b0b0" : "white"
                border.width: 1
                border.color: "#808080"

                // typed digits are only the givens; own entries stay as the handwriting
                // that was written, recognized silently for the game logic
                Text {
                    anchors.centerIn: parent
                    visible: cellRect.isGiven
                    text: cellRect.value === 0 ? "" : cellRect.value
                    font.pixelSize: Math.round(grid.cell * 0.62)
                    font.bold: true
                    color: "black"
                }

                // ghost candidates: a 3x3 grid of small numbers in empty cells. In ghost mode
                // all nine show (off = grey, on = blue); otherwise only the switched-on ones.
                Repeater {
                    model: (root.rev >= 0 && cellRect.value === 0 && !cellRect.isGiven
                            && (root.ghostMode || root.ghosts[cellRect.idx] !== 0)) ? 9 : 0
                    delegate: Text {
                        property bool on: root.rev >= 0 && (root.ghosts[cellRect.idx] & (1 << index)) !== 0
                        visible: root.ghostMode || on
                        x: (index % 3) * cellRect.width / 3
                        y: Math.floor(index / 3) * cellRect.height / 3
                        width: cellRect.width / 3
                        height: cellRect.height / 3
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: index + 1
                        font.pixelSize: Math.round(grid.cell * 0.22)
                        font.bold: on
                        color: on ? "#1f4fd8" : "#c4c4c4"
                    }
                }

                // X marker for entries flagged by Check
                Text {
                    visible: cellRect.isWrong
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    text: "X"
                    font.pixelSize: Math.round(grid.cell * 0.3)
                    font.bold: true
                    color: "#a00000"
                }
            }
        }

        // thick 3x3 box borders, drawn above the cells
        Repeater {
            model: 4
            delegate: Rectangle {
                x: index * grid.cell * 3 - (index === 3 ? 6 : (index === 0 ? 0 : 3))
                y: 0
                width: 6
                height: grid.height
                color: "black"
            }
        }
        Repeater {
            model: 4
            delegate: Rectangle {
                x: 0
                y: index * grid.cell * 3 - (index === 3 ? 6 : (index === 0 ? 0 : 3))
                width: grid.width
                height: 6
                color: "black"
            }
        }

        // committed handwriting: one transparent canvas per cell, a little larger than the
        // cell so digits that overflow it are not cut off; repainted only when that cell changes
        Repeater {
            id: inkCanvases
            model: 81
            delegate: Canvas {
                property int idx: index
                property real pad: Math.round(grid.cell * 0.25)
                x: (idx % 9) * grid.cell - pad
                y: Math.floor(idx / 9) * grid.cell - pad
                width: grid.cell + 2 * pad
                height: grid.cell + 2 * pad
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    root.paintCellInk(ctx, idx, x, y);
                }
            }
        }

        // live ink while writing: plain dots (the panel refreshes them fast). At commit
        // they are replaced by the smooth lines above.
        ListModel { id: inkDots }
        Repeater {
            model: inkDots
            delegate: Rectangle {
                x: px - width / 2
                y: py - height / 2
                width: Math.max(4, Math.round(grid.cell * 0.05))
                height: width
                radius: width / 2
                color: "black"
            }
        }

        // blue frame while ghost mode is on
        Rectangle {
            anchors.fill: parent
            anchors.margins: -10
            color: "transparent"
            border.width: 6
            border.color: "#1f4fd8"
            visible: root.ghostMode
        }

        // refresh flash layer: black patches over changed cells (see flashRect), no input handling
        ListModel { id: flashModel }
        Repeater {
            model: flashModel
            delegate: Rectangle {
                id: patch
                property bool fading: false
                // Two steps: turn transparent (the cell below is redrawn while the patch's
                // Content area still covers it, so it is not repainted in UFast, which
                // tints the cells yellow), then remove the patch.
                Timer { running: true; interval: 300; onTriggered: patch.fading = true }
                Timer {
                    running: true
                    interval: 700
                    onTriggered: {
                        for (var k = 0; k < flashModel.count; k++)
                            if (flashModel.get(k).uid === uid) { flashModel.remove(k); break; }
                    }
                }
                x: fx
                y: fy
                width: fw
                height: fh
                color: fading ? "transparent" : "black"
                z: 50
                DisplayMethodArea {
                    anchors.fill: parent
                    displayMethod: DisplayMethodArea.Content
                }
            }
        }

        // ultra-fast panel refresh, only while ink is live; otherwise it would override the
        // nested Content areas of the flash patches and the ghosting would stay
        DisplayMethodArea {
            anchors.fill: parent
            displayMethod: DisplayMethodArea.UFast   // keep constant: switching modes at pen-down stalls ~300 ms
        }

        // MouseArea, not PointHandler: on the device PointHandler delivers one broken
        // press for the pen and then stops, while MouseArea gets the whole stroke
        // (pen and finger both arrive as real mouse events).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: function (m) { root.penPress(m.x, m.y, m.source); }
            onPositionChanged: function (m) { root.penMove(m.x, m.y); }
            onReleased: root.penRelease()
            onCanceled: root.penRelease()
        }
    }

    // ---- handwriting directly on the board ----
    // Strokes are shown as dots while writing. After a short idle (or when the next stroke
    // starts somewhere else) the ink is committed: in write mode it is recognized as one
    // digit and written into the cell under it; in notes mode it is kept as a note. Either
    // way the dots are replaced by smoothed lines.
    property var strokes: []          // strokes of the piece being written, {x, y} in grid pixels
    property var curStroke: null
    property var lastDot: null        // last point that got an ink dot
    readonly property real minInkSize: Math.max(24, grid.cell * 0.3)   // smaller ink is not a digit
    readonly property real tapSize: 14                                  // a single stroke smaller than this is a tap
    property var eraseBefore: ({})                                      // cell -> snapshot, for the current erase stroke
    property var eraseInk: ({})                                         // cells whose ink the current erase stroke cut
    property var eraseDirty: ({})                                       // cells waiting for a canvas repaint
    property var eraseLast: null
    readonly property real eraserR: Math.max(10, grid.cell * 0.11)
    property bool tapActive: false                                      // ghost mode: a press that may be a tap
    property bool tapMoved: false
    property var tapStart: null

    // Finished pieces wait here (their dots stay on screen) and are recognised later, one at a
    // time, while the pen is idle: recognising takes long and blocked the next stroke.
    property var pieces: []        // [{id, strokes}]
    property int pieceId: 0        // id of the piece being written (tags its dots)
    function addDot(x, y) {
        inkDots.append({px: x, py: y, pid: pieceId});
        lastDot = {x: x, y: y};
    }
    function dropDots(id) {
        for (var i = inkDots.count - 1; i >= 0; i--) if (inkDots.get(i).pid === id) inkDots.remove(i);
    }
    function queuePiece() {
        pieces.push({id: pieceId, strokes: strokes});
        pieceId++;
        strokes = [];
        curStroke = null;
        lastDot = null;
    }
    readonly property bool penBusy: curStroke !== null || pressPending || erasing || tapActive
    function commitStep() {
        if (penBusy) return;   // endStroke restarts the idle timer
        if (pieces.length > 0) {
            var p = pieces.shift();
            commitPiece(p.strokes, p.id);
        } else if (strokes.length > 0) {
            commitPiece(strokes, pieceId);
        }
        if (pieces.length > 0 || strokes.length > 0) drainTimer.restart();
    }
    Timer { id: drainTimer; interval: 60; repeat: false; onTriggered: root.commitStep() }

    function inkBounds() {
        return boundsOf(strokes);
    }

    function cellAt(x, y) {
        var c = Math.floor(x / grid.cell), r = Math.floor(y / grid.cell);
        if (c < 0 || c > 8 || r < 0 || r > 8) return -1;
        return r * 9 + c;
    }

    // discards the live ink (committed handwriting stays)
    function clearInk() {
        commitTimer.stop();
        drainTimer.stop();
        strokes = [];
        pieces = [];
        curStroke = null;
        lastDot = null;
        inkLive = false;
        inkDots.clear();
    }
    // discards only the piece being written (queued pieces stay)
    function discardPiece(id) {
        dropDots(id);
        if (id === pieceId) {
            strokes = [];
            curStroke = null;
            lastDot = null;
        }
        inkLive = inkDots.count > 0;
    }
    // discards everything: live ink, all committed handwriting and ghosts (new game)
    function clearAllInk() {
        clearInk();
        for (var c = 0; c < 81; c++) {
            var s = inkStore[c];
            if (s && s.length > 0) {
                inkStore[c] = [];
                repaintInk(c);
            }
        }
        if (inkStore.length === 0) inkStore = emptyStore();
        var g = [];
        for (var i = 0; i < 81; i++) g.push(0);
        ghosts = g;
    }
    // commits any ink that is still waiting for its idle timeout
    function flushLive() {
        commitTimer.stop();
        drainTimer.stop();
        while (pieces.length > 0) {
            var p = pieces.shift();
            commitPiece(p.strokes, p.id);
        }
        if (strokes.length > 0) commitPiece(strokes, pieceId);
    }

    // which of a cell's nine candidate slots (row*3+col) lies under a grid position
    function slotAt(c, x, y) {
        var lx = x - (c % 9) * grid.cell, ly = y - Math.floor(c / 9) * grid.cell;
        var col = Math.max(0, Math.min(2, Math.floor(lx / (grid.cell / 3))));
        var row = Math.max(0, Math.min(2, Math.floor(ly / (grid.cell / 3))));
        return row * 3 + col;
    }

    // ghost mode: tap switches the candidate under the pen/finger on or off
    function toggleGhost(x, y) {
        var c = cellAt(x, y);
        if (c < 0 || givens[c] || cells[c] !== 0 || solved) return;
        var before = snap(c);
        setGhost(c, ghosts[c] ^ (1 << slotAt(c, x, y)));
        recordChange(c, before);
        rev++;
    }

    // The rubber: removes only the parts of strokes under the eraser disc. The eraser is
    // interpolated between events so fast moves leave no gaps.
    function eraseAt(x, y) {
        if (eraseLast === null) {
            eraseDisc(x, y);
        } else {
            var dx = x - eraseLast.x, dy = y - eraseLast.y;
            var steps = Math.max(1, Math.ceil(Math.sqrt(dx * dx + dy * dy) / (eraserR / 2)));
            for (var i = 1; i <= steps; i++) eraseDisc(eraseLast.x + dx * i / steps, eraseLast.y + dy * i / steps);
        }
        eraseLast = {x: x, y: y};
        if (!eraseRepaintTimer.running) eraseRepaintTimer.start();
    }
    function eraseDisc(x, y) {
        if (solved) return;
        if (ghostMode) {
            // the eraser switches the candidate under it off
            var gc = cellAt(x, y);
            if (gc < 0 || givens[gc] || cells[gc] !== 0) return;
            var bit = 1 << slotAt(gc, x, y);
            if ((ghosts[gc] & bit) === 0) return;
            if (eraseBefore[gc] === undefined) eraseBefore[gc] = snap(gc);
            setGhost(gc, ghosts[gc] & ~bit);
            rev++;
            return;
        }
        var m = eraserR + grid.cell * 0.3;   // ink can overflow its cell
        var c0 = Math.max(0, Math.floor((x - m) / grid.cell)), c1 = Math.min(8, Math.floor((x + m) / grid.cell));
        var r0 = Math.max(0, Math.floor((y - m) / grid.cell)), r1 = Math.min(8, Math.floor((y + m) / grid.cell));
        for (var r = r0; r <= r1; r++) {
            for (var c = c0; c <= c1; c++) {
                var i = r * 9 + c;
                if (givens[i] || inkStore[i].length === 0) continue;
                var cut = cutStrokes(inkStore[i], x, y, eraserR);
                if (cut === null) continue;
                if (eraseBefore[i] === undefined) eraseBefore[i] = snap(i);
                inkStore[i] = cut;
                eraseInk[i] = true;
                eraseDirty[i] = true;
            }
        }
    }
    function repaintDirty() {
        for (var k in eraseDirty) repaintInk(parseInt(k));
        eraseDirty = ({});
    }
    Timer {
        id: eraseRepaintTimer
        interval: 40
        repeat: false
        onTriggered: root.repaintDirty()
    }

    function beginStroke(x, y) {
        if (penTool === "eraser") {
            flushLive();
            erasing = true;
            eraseBefore = ({});
            eraseInk = ({});
            eraseLast = null;
            eraseAt(x, y);
            return;
        }
        if (ghostMode) {
            // pen strokes do nothing here; a press without movement is a tap
            tapActive = true;
            tapMoved = false;
            tapStart = {x: x, y: y};
            return;
        }
        commitTimer.stop();
        drainTimer.stop();
        var b = inkBounds();
        if (b !== null) {
            var m = grid.cell * 0.2;
            // pressed away from the piece being written: that one is finished, queue it
            if (x < b.minX - m || x > b.maxX + m || y < b.minY - m || y > b.maxY + m) queuePiece();
        }
        inkLive = true;
        curStroke = [{x: x, y: y}];
        strokes.push(curStroke);
        strokesChanged();
        addDot(x, y);
    }
    function addPoint(x, y) {
        if (erasing) { eraseAt(x, y); return; }
        if (tapActive) {
            var tx = x - tapStart.x, ty = y - tapStart.y;
            if (tx * tx + ty * ty > tapSize * tapSize) tapMoved = true;
            return;
        }
        if (curStroke === null) return;   // no press seen (stray move)
        var last = curStroke[curStroke.length - 1];
        var dx = x - last.x, dy = y - last.y;
        if (dx * dx + dy * dy < 2) return;   // ignore moves under ~1.4 px
        curStroke.push({x: x, y: y});
        var ex = x - lastDot.x, ey = y - lastDot.y;
        var dist = Math.sqrt(ex * ex + ey * ey);
        if (dist >= 2.5) {
            // fill the segment with dots, so a big jump between two events (the first events
            // after a press arrive late) still draws a continuous line
            var n = Math.floor(dist / 2.5), fx = lastDot.x, fy = lastDot.y;
            for (var t = 1; t <= n; t++) inkDots.append({px: fx + ex * t / n * (n * 2.5 / dist), py: fy + ey * t / n * (n * 2.5 / dist), pid: pieceId});
            lastDot = {x: fx + ex * (n * 2.5 / dist), y: fy + ey * (n * 2.5 / dist)};
        }
    }
    function endStroke() {
        if (erasing) {
            erasing = false;
            eraseLast = null;
            eraseRepaintTimer.stop();
            var ch = [];
            var msg = "";
            for (var key in eraseBefore) {
                var c = parseInt(key);
                if (eraseInk[c] === true) {
                    // re-read what is left of the handwriting
                    var ink = inkStore[c], nv = 0;
                    if (ink.length > 0) {
                        var bb = boundsOf(ink);
                        if (bb.size >= minInkSize) {
                            var res = readCell(recognizeList(ink), c);
                            if (res.confidence >= 0.5 || res.tie) nv = res.digit;
                        }
                    }
                    setValueOnly(c, nv);
                    msg = nv === 0 ? "Erased" : "Cell now reads " + nv;
                }
                repaintInk(c);
                ch.push({c: c, before: eraseBefore[key], after: snap(c)});
                if (refreshAfterWrite && eraseInk[c] === true) flashCell(c);
            }
            eraseBefore = ({});
            eraseInk = ({});
            eraseDirty = ({});
            if (msg !== "") message = msg;
            recordAction(ch);
            rev++;
            return;
        }
        if (tapActive) {
            tapActive = false;
            if (!tapMoved) toggleGhost(tapStart.x, tapStart.y);
            return;
        }
        if (curStroke === null) return;
        curStroke = null;
        var b = inkBounds();
        if (strokes.length === 1 && b.size < tapSize) {
            // a tap does nothing (there is no cell selection); wipe the dot it left
            if (refreshAfterWrite) flashInk(b);
            discardPiece(pieceId);
            if (pieces.length > 0) commitTimer.restart();
            return;
        }
        commitTimer.restart();
    }

    // Draws the strokes as filled discs into a grey array (black ink on white),
    // scaled so the digit is about 200 raster pixels tall whatever size it was written.
    function recognizeList(list) {
        var b = boundsOf(list);
        var scale = 100 / Math.max(b.size, 1);   // half of the old 200 px: about 4x cheaper, the model sees 20x20 anyway
        var margin = 8;
        var w = Math.ceil((b.maxX - b.minX) * scale) + 2 * margin;
        var h = Math.ceil((b.maxY - b.minY) * scale) + 2 * margin;
        var px = new Array(w * h);
        var n;
        for (n = 0; n < w * h; n++) px[n] = 255;
        var r = 3.25, r2 = r * r;
        function stamp(cx, cy) {
            var x0 = Math.max(0, Math.floor(cx - r)), x1 = Math.min(w - 1, Math.ceil(cx + r));
            var y0 = Math.max(0, Math.floor(cy - r)), y1 = Math.min(h - 1, Math.ceil(cy + r));
            for (var yy = y0; yy <= y1; yy++) {
                for (var xx = x0; xx <= x1; xx++) {
                    var ddx = xx + 0.5 - cx, ddy = yy + 0.5 - cy;
                    if (ddx * ddx + ddy * ddy <= r2) px[yy * w + xx] = 0;
                }
            }
        }
        for (var s = 0; s < list.length; s++) {
            var st = list[s];
            var prev = null;
            for (var k = 0; k < st.length; k++) {
                var cx = (st[k].x - b.minX) * scale + margin, cy = (st[k].y - b.minY) * scale + margin;
                if (prev === null) {
                    stamp(cx, cy);
                } else {
                    var ex = cx - prev.x, ey = cy - prev.y;
                    var steps = Math.max(1, Math.ceil(Math.sqrt(ex * ex + ey * ey) / 1.2));
                    for (var t = 1; t <= steps; t++) stamp(prev.x + ex * t / steps, prev.y + ey * t / steps);
                }
                prev = {x: cx, y: cy};
            }
        }
        return Recognizer.recognize(Recognizer.preprocess(px, w, h));
    }

    // wipes the live ink again (rejected or too small), optionally telling why
    function rejectInk(b, why, id) {
        if (refreshAfterWrite) flashInk(b);
        discardPiece(id);
        if (why !== "") message = why;
    }

    // Commits one finished piece of ink (its strokes) to the cell under it.
    function commitPiece(live, id) {
        var b = boundsOf(live);
        if (b === null) return;
        var cell = cellAt((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2);
        if (cell < 0) { rejectInk(b, "", id); return; }
        if (b.size < minInkSize) { rejectInk(b, "", id); return; }
        var raw = recognizeList(live);
        if (raw.confidence < 0.5) { rejectInk(b, "Not sure (" + Math.round(raw.confidence * 100) + "%). Write the digit again.", id); return; }
        var res = readCell(raw, cell);
        var pct = Math.round(res.confidence * 100);
        if (givens[cell]) { rejectInk(b, "That cell is a given.", id); return; }
        if (solved) { rejectInk(b, "", id); return; }
        var before = snap(cell);
        // the handwriting STAYS as written (smoothed and densified once, replacing what was
        // written there before)
        var stored = [];
        for (var si = 0; si < live.length; si++) stored.push(densify(smoothPoints(live[si]), 2.5));
        inkStore[cell] = stored;
        setValueOnly(cell, res.digit);
        updateSolved();
        if (!solved) message = "Read " + res.digit + " (" + pct + "% sure)" + (res.tie ? ", not " + res.best + " (clashes)" : "");

        recordChange(cell, before);
        // live dots are replaced by the smoothed lines of the committed ink
        discardPiece(id);
        repaintInk(cell);
        if (refreshAfterWrite) {
            flashInk(b);
            flashCell(cell);
        }
        rev++;
    }

    Timer {
        id: commitTimer
        interval: 550
        repeat: false
        onTriggered: root.commitStep()
    }

    // ---- buttons ----
    Grid {
        id: toolRow
        anchors.top: grid.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 4
        spacing: 16
        property real bw: Math.floor((grid.width - 3 * 16) / 4)

        Btn {
            width: toolRow.bw; height: 128
            label: "Ghost"
            icon: "ghost"
            active: root.ghostMode
            activeColor: root.accent
            onClicked: { root.flushLive(); root.ghostMode = !root.ghostMode; root.rev++; }
        }
        Btn {
            width: toolRow.bw; height: 128
            label: "Undo"
            icon: "undo"
            dim: !root.canUndo
            onClicked: root.undo()
        }
        Btn {
            width: toolRow.bw; height: 128
            label: "Redo"
            icon: "redo"
            dim: !root.canRedo
            onClicked: root.redo()
        }
        Btn {
            width: toolRow.bw; height: 128
            label: "Check"
            icon: "check"
            onClicked: root.checkBoard()
        }
    }

    Grid {
        id: gameRow
        anchors.top: toolRow.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 2
        spacing: 16
        property real bw: Math.floor((grid.width - 16) / 2)

        Btn {
            width: gameRow.bw; height: 128
            label: "New game"
            icon: "plus"
            kind: "solid"
            onClicked: root.requestPanel("open")
        }
        Btn {
            width: gameRow.bw; height: 128
            label: "Restart"
            icon: "restart"
            onClicked: root.restartPuzzle()
        }
    }

    // ---- New game panel ----
    Rectangle {
        id: panel
        anchors.fill: parent
        color: "white"
        visible: root.panelOpen
        z: 500

        MouseArea { anchors.fill: parent }   // swallows input so nothing underneath reacts

        Column {
            id: pcol
            x: 60
            y: 90
            width: root.width - 120
            spacing: 20

            Text { text: "New game"; font.pixelSize: 72; font.weight: Font.Bold; color: root.ink }
            Text { text: "Pick a difficulty and start a fresh puzzle."; font.pixelSize: 30; color: root.mute }
            Item { width: 1; height: 24 }

            Text { text: "DIFFICULTY"; font.pixelSize: 26; font.weight: Font.DemiBold; font.letterSpacing: 4; color: root.mute }
            // segmented control
            Rectangle {
                id: seg
                width: parent.width; height: 120; radius: 28
                color: root.tileBg
                property var names: ["Easy", "Medium", "Hard", "Expert"]
                property var vals: [40, 32, 26, 22]
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            width: seg.width / 4; height: seg.height
                            radius: 28
                            color: root.givensTarget === seg.vals[index] ? root.ink : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: seg.names[index]
                                font.pixelSize: 32
                                font.weight: root.givensTarget === seg.vals[index] ? Font.DemiBold : Font.Medium
                                color: root.givensTarget === seg.vals[index] ? "white" : root.ink
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.givensTarget = seg.vals[index] }
                        }
                    }
                }
            }

            // stepper
            Item {
                width: parent.width; height: 120
                Btn { id: minus; width: 120; height: 120; radius: 60; label: "−"; fontPx: 56; dim: root.givensTarget <= 20; onClicked: root.givensTarget = Math.max(20, root.givensTarget - 1) }
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.givensTarget; font.pixelSize: 64; font.weight: Font.Bold; color: root.ink }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "clues  ·  fewer is harder"; font.pixelSize: 26; color: root.mute }
                }
                Btn { width: 120; height: 120; radius: 60; anchors.right: parent.right; label: "+"; fontPx: 56; dim: root.givensTarget >= 60; onClicked: root.givensTarget = Math.min(60, root.givensTarget + 1) }
            }

            Item { width: 1; height: 24 }
            Text { text: "OPTIONS"; font.pixelSize: 26; font.weight: Font.DemiBold; font.letterSpacing: 4; color: root.mute }
            Toggle {
                width: parent.width
                label: "Show errors live"
                hint: "Mark conflicting digits as you write"
                on: root.liveErrors
                onToggled: { root.liveErrors = !root.liveErrors; root.rev++; }
            }
            Toggle {
                width: parent.width
                label: "Clean refresh"
                hint: "Clear screen ghosting after changes"
                on: root.refreshAfterWrite
                onToggled: root.refreshAfterWrite = !root.refreshAfterWrite
            }
            Item { width: 1; height: 24 }

            Row {
                spacing: 20
                property real bw: Math.floor((parent.width - 20) / 2)
                Btn { width: parent.bw; height: 140; label: "Cancel"; fontPx: 38; onClicked: root.requestPanel("close") }
                Btn { width: parent.bw; height: 140; label: "Start"; fontPx: 38; kind: "solid"; onClicked: root.requestPanel("start") }
            }
        }
    }

    // ---- full-screen black flash for view switches (topmost) ----
    Rectangle {
        anchors.fill: parent
        z: 1000
        color: "black"
        visible: root.flashing
        DisplayMethodArea {
            anchors.fill: parent
            displayMethod: DisplayMethodArea.Content
        }
        MouseArea { anchors.fill: parent }   // swallow taps while the flash is active
    }
}
