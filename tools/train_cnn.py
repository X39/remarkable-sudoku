"""Train the Sudoku digit CNN and write ui/digit-model.js.

Data: MNIST (preprocessed like the app does, augmented on the fly) + synthetic pen-stroke digits
in writing styles MNIST lacks (flagged / serifed 1, barred 7, open and closed 4, 9 with straight
tail), rendered with the same rasterizer as recognizeList() in sudoku.qml.
The operator's real samples (tools/user-samples/*.json) are NEVER trained on: they are the test set.

Usage: python -I tools/train_cnn.py [c1=16] [c2=32] [fc=128] [epochs=25] [write]
"""
import math
import os
import sys
from multiprocessing import Pool

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import train_digit as td  # noqa: E402
import train_user as tu  # noqa: E402

ROOT = td.ROOT
SYN_PER_CLASS = int(os.environ.get("SYN", "4000"))
SYN_CACHE = os.path.join(ROOT, "build", "data", "synthetic_%d.npz" % SYN_PER_CLASS)


# ---------------------------------------------------------------- synthetic strokes
def spline(pts, per=8):
    """Catmull-Rom through control points -> dense polyline."""
    p = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    out.append(pts[-1])
    return out


def line(a, b, n=6):
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


def poly(pts, curved):
    if curved:
        return spline(pts)
    out = []
    for a, b in zip(pts[:-1], pts[1:]):
        out += line(a, b)
    return out


def ellipse(cx, cy, rx, ry, a0, a1, n=36):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def gen1(r):
    sx = 50 + r.normal(0, 5)
    style = r.choice(["stick", "us", "long", "arch", "serif", "curved", "hoop"], p=[.1, .12, .14, .2, .08, .08, .28])
    lean = r.uniform(-8, 8)
    top, bot = (sx + lean, r.uniform(0, 6)), (sx - lean, 100 - r.uniform(0, 5))
    if style == "hoop":
        # round "n"-shaped flag: the stroke starts low on the left, arches over and runs down into the stem
        # (user's 1s that read as 7: left leg drops 0.2-0.45 of the height, apex above the stem)
        rx = r.uniform(14, 40)
        ry = min(rx * r.uniform(0.5, 1.3), 45)
        a0 = r.uniform(130, 200)
        a1 = 270 + r.uniform(5, 60)
        cx, cy = top[0] - rx * math.sin(math.radians(a1 - 270)), top[1] + ry + r.uniform(0, 4)
        arc = ellipse(cx, cy, rx, ry, a0, a1, 14)
        e = arc[-1]
        stem = [e, (e[0] + r.uniform(-3, 3) - lean * .5, 50), (bot[0] + r.uniform(-2, 2), 100 - r.uniform(0, 5))]
        pts = spline(arc[::2] + stem[1:], 4)
        return [pts]
    if style == "stick":
        return [poly([top, bot], r.random() < .3)]
    if style in ("us", "serif"):
        L = r.uniform(12, 30)
    elif style == "long":
        L = r.uniform(28, 52)
    elif style == "arch":
        L = r.uniform(30, 80)      # long rounded flag: tip low and far left, arching over the stem
    else:
        L = r.uniform(15, 40)
    if style == "arch":
        drop = L * r.uniform(0.25, 0.8)
        tip = (top[0] - L, top[1] + drop)
        midp = (top[0] - L * r.uniform(0.45, 0.65), top[1] + drop * r.uniform(0.2, 0.45))
        shoulder = (top[0] - r.uniform(2, 8), top[1] - r.uniform(0, 3))
        st = [spline([tip, midp, shoulder, (top[0] + r.uniform(0, 4), top[1] + r.uniform(2, 10)), (bot[0] + r.uniform(-2, 2), 50), bot])]
        if r.random() < .12:
            w = r.uniform(15, 30)
            st.append(poly([(bot[0] - w, bot[1]), (bot[0] + w, bot[1])], False))
        return st
    flag = (top[0] - L, top[1] + L * r.uniform(0.5, 1.4))
    st = [poly([flag, top, bot], style == "curved" or r.random() < .2)]
    if style == "serif":
        w = r.uniform(15, 30)
        st.append(poly([(bot[0] - w, bot[1]), (bot[0] + w, bot[1])], False))
    return st


def gen7(r):
    W = r.uniform(50, 90)
    y0 = r.normal(0, 2)
    bar_end = (W, y0 + r.normal(0, 4))
    foot = (W * r.uniform(.2, .6), 100)
    start = (r.normal(0, 2), y0 + r.normal(0, 3))
    curved = r.random() < .35
    mid = ((bar_end[0] + foot[0]) / 2 + r.uniform(-8, 8), 50 + r.uniform(-8, 8))
    two = r.random() < .12
    st = []
    pts = [start, bar_end, mid, foot] if curved else [start, bar_end, foot]
    if r.random() < .2:
        pts = [(start[0], start[1] + r.uniform(6, 16))] + pts
    if two:
        st.append(poly([start, bar_end], False))
        st.append(poly([bar_end, mid, foot] if curved else [bar_end, foot], curved))
    else:
        st.append(poly(pts, curved))
    if r.random() < .3:
        yy = r.uniform(42, 66)
        cx = (bar_end[0] * (1 - yy / 100) + foot[0] * yy / 100)
        w = r.uniform(14, 26)
        st.append(poly([(cx - w, yy), (cx + w, yy)], False))
    return st


def gen4(r):
    sx = r.uniform(62, 80)
    by = r.uniform(58, 76)
    kind = r.choice(["closed", "open", "round", "oneline"], p=[.2, .2, .45, .15])
    stem = [(sx + r.normal(0, 3), r.uniform(0, 8)), (sx + r.normal(0, 3), 100)]
    if kind == "closed":
        return [poly([(sx - r.uniform(0, 8), 0), (r.uniform(0, 10), by), (r.uniform(88, 100), by + r.normal(0, 3))], False),
                poly(stem, False)]
    if kind == "open":
        x0 = r.uniform(0, 18)
        return [poly([(x0, r.uniform(0, 12)), (x0 - r.uniform(0, 6), by), (r.uniform(88, 100), by + r.normal(0, 3))], False),
                poly(stem, False)]
    if kind == "round":   # rounded foot, bar rising to the stem (the shape that looks like a 9)
        x0 = r.uniform(5, 22)
        jy = r.uniform(0.0, 0.55) * 100
        pts = [(x0 + r.uniform(0, 14), r.uniform(0, 6)), (x0 - r.uniform(0, 4), by * .55), (x0, by),
               (x0 + 22, by + r.uniform(-4, 6)), (sx - 14, by - r.uniform(0, 12)), (sx, jy)]
        return [poly(pts, True), poly([(sx, jy), (sx + r.normal(0, 3), 100)], False)] if r.random() < .5 else \
            [poly(pts + [(sx, 100)], True)]
    # one stroke: diagonal, bar, back up the stem and down
    return [poly([(sx, 0), (r.uniform(0, 10), by), (r.uniform(88, 100), by), (sx, 0.0 + r.uniform(0, 20)), (sx, 100)], False)]


def gen9(r):
    cx, cy = 50 + r.normal(0, 3), r.uniform(26, 34)
    rx, ry = r.uniform(20, 32), r.uniform(22, 34)
    a0 = r.uniform(-40, 40)
    gap = r.choice([0, 0, 10, 25])
    a1 = a0 + 360 - gap + r.uniform(0, 20)
    loop = ellipse(cx, cy, rx, ry, a0, a1)
    tx = cx + rx
    bot = (tx + r.uniform(-14, 10), 100)
    if r.random() < .35:
        tail = spline([(tx, cy), (tx - 2, cy + 40), (tx - 10, 85), (tx - r.uniform(15, 30), 98)])
    else:
        tail = line((tx, cy), bot)
    if r.random() < .35:
        return [loop, tail]
    return [loop + tail]


GENS = {1: gen1, 4: gen4, 7: gen7, 9: gen9}


def _syn_job(args):
    digit, seed = args
    r = np.random.default_rng(seed)
    st = GENS[digit](r)
    st = tu.augment(st, r)
    return td.preprocess(tu.raster(st, radius=r.uniform(2.6, 5.0))), digit


def synthetic():
    if os.path.exists(SYN_CACHE):
        z = np.load(SYN_CACHE)
        return z["x"], z["y"]
    jobs = [(d, 1000 * d + i) for d in GENS for i in range(SYN_PER_CLASS)]
    with Pool(20) as p:
        res = p.map(_syn_job, jobs, chunksize=64)
    x = np.stack([a for a, _ in res]).astype(np.float32)
    y = np.array([b for _, b in res])
    np.savez_compressed(SYN_CACHE, x=x, y=y)
    return x, y


# ---------------------------------------------------------------- model
class Net(nn.Module):
    def __init__(self, c1, c2, fc):
        super().__init__()
        self.c1 = nn.Conv2d(1, c1, 3)
        self.c2 = nn.Conv2d(c1, c2, 3)
        self.f1 = nn.Linear(c2 * 25, fc)
        self.f2 = nn.Linear(fc, 10)

    def forward(self, x):
        x = F.max_pool2d(F.relu(self.c1(x)), 2)
        x = F.max_pool2d(F.relu(self.c2(x)), 2)
        x = F.relu(self.f1(x.flatten(1)))
        return self.f2(x)


def augment_batch(x, g):
    n = x.shape[0]
    th = (torch.rand(n, generator=g) * 2 - 1) * math.radians(13)
    sh = (torch.rand(n, generator=g) * 2 - 1) * 0.22
    sx = 0.9 + torch.rand(n, generator=g) * 0.25
    sy = 0.9 + torch.rand(n, generator=g) * 0.2
    tx = (torch.rand(n, generator=g) * 2 - 1) * 0.08
    ty = (torch.rand(n, generator=g) * 2 - 1) * 0.08
    c, s = torch.cos(th), torch.sin(th)
    A = torch.zeros(n, 2, 3)
    A[:, 0, 0] = c / sx + sh * s / sy
    A[:, 0, 1] = -s / sx + sh * c / sy
    A[:, 1, 0] = s / sy
    A[:, 1, 1] = c / sy
    A[:, 0, 2] = tx
    A[:, 1, 2] = ty
    grid = F.affine_grid(A, x.shape, align_corners=False)
    x = F.grid_sample(x, grid, align_corners=False, padding_mode="zeros")
    thick = (torch.rand(n, 1, 1, 1, generator=g) < 0.4).float()
    x = thick * F.max_pool2d(x, 3, 1, 1) + (1 - thick) * x
    return x.clamp(0, 1)


def acc19(net, X, y):
    net.eval()
    with torch.no_grad():
        z = net(X)
    pred = z[:, 1:].argmax(1) + 1
    m = y >= 1
    return float((pred[m] == y[m]).float().mean()), pred


def fmt(a):
    return "[" + ",".join(("%.3f" % v).replace("-0.000", "0.000") for v in a.detach().numpy().ravel()) + "]"


def main():
    args = {a.split("=")[0]: a.split("=")[1] for a in sys.argv[1:] if "=" in a}
    c1, c2, fc, epochs = int(args.get("c1", 16)), int(args.get("c2", 32)), int(args.get("fc", 128)), int(args.get("epochs", 25))
    torch.manual_seed(1)
    g = torch.Generator().manual_seed(2)
    p, y, pt, yt = tu.mnist_pre()
    sx, sy_ = synthetic()
    print("mnist", p.shape, "synthetic", sx.shape, flush=True)
    X = torch.from_numpy(np.concatenate([p, sx]).astype(np.float32)).unsqueeze(1)
    Y = torch.from_numpy(np.concatenate([y, sy_]).astype(np.int64))
    Xt = torch.from_numpy(pt.astype(np.float32)).unsqueeze(1)
    Yt = torch.from_numpy(yt.astype(np.int64))
    users = tu.load_samples()
    Xu = torch.from_numpy(np.stack([td.preprocess(tu.raster(tu.to_points(s["strokes"]))) for s in users]).astype(np.float32)).unsqueeze(1)
    Yu = torch.tensor([s["label"] for s in users])
    net = Net(c1, c2, fc)
    print("params", sum(q.numel() for q in net.parameters()), flush=True)
    opt = torch.optim.AdamW(net.parameters(), 2e-3, weight_decay=1e-4)
    steps = epochs * math.ceil(len(X) / 256)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, 4e-3, total_steps=steps)
    for ep in range(epochs):
        net.train()
        perm = torch.randperm(len(X), generator=g)
        tot = 0.0
        for i in range(0, len(X), 256):
            idx = perm[i:i + 256]
            xb = augment_batch(X[idx], g)
            loss = F.cross_entropy(net(xb), Y[idx], label_smoothing=0.05)
            opt.zero_grad()
            loss.backward()
            opt.step()
            sched.step()
            tot += float(loss) * len(idx)
        if ep % 3 == 2 or ep == epochs - 1:
            am, _ = acc19(net, Xt, Yt)
            au, pu = acc19(net, Xu, Yu)
            print("ep %d loss %.4f mnist %.4f user %d/%d" % (ep + 1, tot / len(X), am, int((pu == Yu).sum()), len(Yu)), flush=True)
    am, _ = acc19(net, Xt, Yt)
    au, pu = acc19(net, Xu, Yu)
    for s, a in zip(users, pu.tolist()):
        if a != s["label"]:
            print("   user miss: wrote %d read %d (cell %s)" % (s["label"], a, s.get("cell")))
    # weights rounded to 3 decimals, as shipped
    with torch.no_grad():
        for q in net.parameters():
            q.copy_(torch.round(q * 1000) / 1000)
    am3, _ = acc19(net, Xt, Yt)
    au3, pu3 = acc19(net, Xu, Yu)
    print("FINAL mnist %.4f (rounded %.4f)  user %d/%d (rounded %d/%d)" %
          (am, am3, int((pu == Yu).sum()), len(Yu), int((pu3 == Yu).sum()), len(Yu)))
    if "write" in sys.argv:
        body = "// GENERATED by tools/train_cnn.py - do not edit.\n"
        body += "// CNN: 28x28 -> conv3x3(%d)+ReLU+pool2 -> conv3x3(%d)+ReLU+pool2 -> fc %d (ReLU) -> 10.\n" % (c1, c2, fc)
        body += "// Trained on MNIST + synthetic pen strokes (1,4,7,9 styles). MNIST test acc (1-9, 3-decimal weights): %.2f%%\n" % (am3 * 100)
        body += ".pragma library\n"
        body += "var DigitModel = {kind: 'cnn', c1: %d, c2: %d, fc: %d, accuracy19: %.4f,\n" % (c1, c2, fc, am3)
        body += "w1: %s,\nb1: %s,\nw2: %s,\nb2: %s,\nw3: %s,\nb3: %s,\nw4: %s,\nb4: %s};\n" % (
            fmt(net.c1.weight), fmt(net.c1.bias), fmt(net.c2.weight), fmt(net.c2.bias),
            fmt(net.f1.weight), fmt(net.f1.bias), fmt(net.f2.weight), fmt(net.f2.bias))
        with open(td.OUT, "w", newline="\n") as f:
            f.write(body)
        print("wrote", td.OUT, len(body), "bytes")


if __name__ == "__main__":
    main()
