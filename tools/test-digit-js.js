// Node test for ui/digit-recognizer.js against the MNIST test set.
// Usage: node tools/test-digit-js.js   (needs build/data/mnist.npz and tools/.venv)
var fs = require("fs");
var path = require("path");
var cp = require("child_process");
var root = path.join(__dirname, "..");
var ui = path.join(root, "ui");

function stripQt(text) {
    return text.split("\n").filter(function (l) { return !/^\.(pragma|import)/.test(l); }).join("\n");
}
var model = new Function(stripQt(fs.readFileSync(path.join(ui, "digit-model.js"), "utf8")) +
    "\nreturn DigitModel;")();
var R = new Function("ModelLib", stripQt(fs.readFileSync(path.join(ui, "digit-recognizer.js"), "utf8")) +
    "\nreturn {preprocess: preprocess, recognize: recognize};")({DigitModel: model});

// Raw MNIST test set (10000 labels then 10000*784 bytes) exported once via python.
var bin = path.join(root, "build", "data", "mnist_test.bin");
if (!fs.existsSync(bin)) {
    cp.execFileSync(process.env.PYTHON || "python3", ["-I", "-c",
        "import numpy as np,sys;d=np.load(sys.argv[1]);open(sys.argv[2],'wb').write(d['y_test'].tobytes()+d['x_test'].tobytes())",
        path.join(root, "build", "data", "mnist.npz"), bin]);
}
var buf = fs.readFileSync(bin);
var n = 10000, okPre = 0, okRaw = 0, tot = 0, i, p;
for (i = 0; i < n; i++) {
    var y = buf[i];
    if (y < 1) continue;
    var raw = [], grey = [];
    for (p = 0; p < 784; p++) {
        var v = buf[n + i * 784 + p];
        raw.push(v / 255);
        grey.push(255 - v); // MNIST is white-on-black; make it black-on-white like the app
    }
    tot++;
    if (R.recognize(R.preprocess(grey, 28, 28)).digit === y) okPre++;
    if (R.recognize(raw).digit === y) okRaw++;
}
console.log("JS acc 1-9, raw white-on-black 28x28 (no preprocess): " + (100 * okRaw / tot).toFixed(2) + "%");
console.log("JS acc 1-9, via preprocess (inverted black-on-white): " + (100 * okPre / tot).toFixed(2) + "% (" + okPre + "/" + tot + ")");

// Synthetic black-on-white 7 in 200x200: thick top bar and diagonal.
var W = 200, px = [];
for (i = 0; i < W * W; i++) px.push(255);
function dot(cx, cy, r) {
    for (var yy = Math.floor(cy - r); yy <= cy + r; yy++)
        for (var xx = Math.floor(cx - r); xx <= cx + r; xx++)
            if (xx >= 0 && yy >= 0 && xx < W && yy < W &&
                (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= r * r) px[yy * W + xx] = 0;
}
function line(x0, y0, x1, y1, r) {
    for (var t = 0; t <= 1; t += 0.002) dot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r);
}
line(50, 50, 150, 50, 7);
line(150, 50, 80, 160, 7);
var res = R.recognize(R.preprocess(px, W, W));
console.log("synthetic 7 -> digit " + res.digit + ", confidence " + res.confidence.toFixed(3));
console.log("scores 1..9: " + res.scores.map(function (s) { return s.toFixed(3); }).join(" "));
