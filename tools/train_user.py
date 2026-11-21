"""Retrain the Sudoku digit model with the operator's own handwriting mixed into MNIST.

Samples live in tools/user-samples/*.json: [{"label": 1-9, "strokes": [[x,y,x,y,...], ...]}].
Collect them by pulling /home/root/.local/share/sudoku/save.json after a finished game
(cells that carry ink, label = the solution digit; see the skill file).

Usage (from the repo root):
  python tools/train_user.py cv      # 2-fold check on the user samples
  python tools/train_user.py train   # final model -> digit-model.js

Strokes are augmented (rotation, shear, aspect, thickness, jitter) and rasterized exactly like
recognizeList() in sudoku.qml (longest side = 100 px, disc radius ~3.25, then the shared preprocess).
"""
import glob
import json
import math
import os
import sys

import numpy as np
from sklearn.neural_network import MLPClassifier

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import train_digit as td  # noqa: E402

ROOT = td.ROOT
CACHE = os.path.join(ROOT, "build", "data", "mnist_pre_train.npz")
AUG = int(os.environ.get("AUG", "150"))     # augmented copies per user sample
SEED = 7


def load_samples():
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, "tools", "user-samples", "*.json"))):
        out += json.load(open(f))
    return out


def raster(strokes, radius=3.25):
    """strokes: list of list of (x, y). Returns white-ink-on-black float image, like the app."""
    pts = [p for s in strokes for p in s]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    scale = 100.0 / max(max(maxx - minx, maxy - miny), 1)
    m = 8
    w = int(math.ceil((maxx - minx) * scale)) + 2 * m
    h = int(math.ceil((maxy - miny) * scale)) + 2 * m
    img = np.zeros((h, w))
    r2 = radius * radius

    def stamp(cx, cy):
        for yy in range(max(0, int(math.floor(cy - radius))), min(h - 1, int(math.ceil(cy + radius))) + 1):
            for xx in range(max(0, int(math.floor(cx - radius))), min(w - 1, int(math.ceil(cx + radius))) + 1):
                if (xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2 <= r2:
                    img[yy, xx] = 1.0

    for s in strokes:
        prev = None
        for (x, y) in s:
            cx, cy = (x - minx) * scale + m, (y - miny) * scale + m
            if prev is None:
                stamp(cx, cy)
            else:
                ex, ey = cx - prev[0], cy - prev[1]
                n = max(1, int(math.ceil(math.hypot(ex, ey) / 1.2)))
                for t in range(1, n + 1):
                    stamp(prev[0] + ex * t / n, prev[1] + ey * t / n)
            prev = (cx, cy)
    return img


def to_points(flat_strokes):
    return [[(s[i], s[i + 1]) for i in range(0, len(s) - 1, 2)] for s in flat_strokes]


def augment(strokes, rng):
    th = math.radians(rng.uniform(-14, 14))
    sh = rng.uniform(-0.25, 0.25)
    sx, sy = rng.uniform(0.85, 1.15), rng.uniform(0.9, 1.1)
    c, s = math.cos(th), math.sin(th)
    out = []
    for st in strokes:
        ns = []
        for (x, y) in st:
            x2, y2 = x + sh * y, y
            x3, y3 = (x2 * c - y2 * s) * sx, (x2 * s + y2 * c) * sy
            ns.append((x3 + rng.normal(0, 0.6), y3 + rng.normal(0, 0.6)))
        out.append(ns)
    return out


def user_set(samples, aug, rng):
    X, Y = [], []
    for sm in samples:
        st = to_points(sm["strokes"])
        X.append(td.preprocess(raster(st)))
        Y.append(sm["label"])
        for _ in range(aug):
            X.append(td.preprocess(raster(augment(st, rng), radius=rng.uniform(2.6, 5.0))))
            Y.append(sm["label"])
    return np.stack(X).reshape(-1, 784), np.array(Y)


def mnist_pre():
    if os.path.exists(CACHE):
        z = np.load(CACHE)
        return z["p"], z["y"], z["pt"], z["yt"]
    d = np.load(td.DATA)
    p = np.stack([td.preprocess(i / 255.0) for i in d["x_train"]])
    pt = np.stack([td.preprocess(i / 255.0) for i in d["x_test"]])
    np.savez_compressed(CACHE, p=p, y=d["y_train"], pt=pt, yt=d["y_test"])
    return p, d["y_train"], pt, d["y_test"]


def fit(Xm, Ym, Xu, Yu, hidden=64):
    X = np.concatenate([Xm, td.dilate(Xm.reshape(-1, 28, 28)).reshape(-1, 784), Xu])
    Y = np.concatenate([Ym, Ym, Yu])
    clf = MLPClassifier(hidden_layer_sizes=(hidden,), activation="relu", solver="adam",
                        batch_size=256, max_iter=30, random_state=1, alpha=1e-4)
    clf.fit(X, Y)
    return clf


def predict19(clf, X):
    P = td.forward(X, clf.coefs_[0], clf.intercepts_[0], clf.coefs_[1], clf.intercepts_[1])
    return P[:, 1:].argmax(axis=1) + 1


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "cv"
    rng = np.random.default_rng(SEED)
    samples = load_samples()
    print("user samples:", len(samples))
    p, y, pt, yt = mnist_pre()
    Xm = p.reshape(-1, 784)
    if mode == "cv":
        # alternate samples inside each label into two folds
        folds = [[], []]
        seen = {}
        for sm in samples:
            k = seen.get(sm["label"], 0)
            seen[sm["label"]] = k + 1
            folds[k % 2].append(sm)
        tot = ok = 0
        for i in (0, 1):
            tr, te = folds[1 - i], folds[i]
            Xu, Yu = user_set(tr, AUG, rng)
            clf = fit(Xm, y, Xu, Yu)
            Xt = np.stack([td.preprocess(raster(to_points(s["strokes"]))) for s in te]).reshape(-1, 784)
            Yt = np.array([s["label"] for s in te])
            pr = predict19(clf, Xt)
            mn = predict19(clf, pt.reshape(-1, 784)[yt >= 1])
            mnacc = float((mn == yt[yt >= 1]).mean())
            print("fold %d: held-out user acc %d/%d, MNIST acc %.4f" % (i, int((pr == Yt).sum()), len(Yt), mnacc))
            for s, a in zip(te, pr):
                if a != s["label"]:
                    print("   miss: wrote %d read %d" % (s["label"], a))
            ok += int((pr == Yt).sum())
            tot += len(Yt)
        print("held-out user accuracy: %d/%d" % (ok, tot))
    else:
        Xu, Yu = user_set(samples, AUG, rng)
        clf = fit(Xm, y, Xu, Yu)
        Xt = np.stack([td.preprocess(raster(to_points(s["strokes"]))) for s in samples]).reshape(-1, 784)
        Yt = np.array([s["label"] for s in samples])
        print("train-set user acc: %d/%d" % (int((predict19(clf, Xt) == Yt).sum()), len(Yt)))
        W1, W2 = clf.coefs_
        b1, b2 = clf.intercepts_
        r = [np.round(a, 3) for a in (W1, b1, W2, b2)]
        a_pre = td.acc19(td.forward(pt.reshape(-1, 784), *r), yt)
        print("MNIST test acc 1-9 (3-decimal weights): %.4f" % a_pre)
        body = "// GENERATED by tools/train_user.py - do not edit.\n"
        body += "// Model: 784 -> 64 (ReLU) -> 10 (softmax), MNIST + %d user samples (augmented x%d).\n" % (len(samples), AUG)
        body += "// Test accuracy (classes 1-9, MNIST test set, preprocessed, 3-decimal weights): %.2f%%\n" % (a_pre * 100)
        body += "// W1 is row-major [784][64], W2 row-major [64][10].\n"
        body += ".pragma library\n"
        body += "var DigitModel = {hidden: 64, accuracy19: %.4f,\n" % a_pre
        body += "W1: %s,\nb1: %s,\nW2: %s,\nb2: %s};\n" % tuple(td.fmt(a) for a in r)
        with open(td.OUT, "w", newline="\n") as f:
            f.write(body)
        print("wrote", td.OUT)


if __name__ == "__main__":
    main()
