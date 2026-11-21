// Accuracy of the shipped JS recognizer on user-sample files. Usage: node tools/eval-samples.js [files...]
// Default: every file in tools/user-samples/. Prints per-file accuracy, a confusion list and the misses.
var fs = require("fs"), path = require("path");
var ui = path.join(__dirname, "..", "ui");
function stripQt(t) { return t.split("\n").filter(function (l) { return !/^\.(pragma|import)/.test(l); }).join("\n"); }
var model = new Function(stripQt(fs.readFileSync(path.join(ui, "digit-model.js"), "utf8")) + "\nreturn DigitModel;")();
var R = new Function("ModelLib", stripQt(fs.readFileSync(path.join(ui, "digit-recognizer.js"), "utf8")) +
    "\nreturn {preprocess: preprocess, recognize: recognize};")({DigitModel: model});
function raster(list, rr) {
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    list.forEach(function (s) { for (var i = 0; i < s.length; i += 2) {
        minX = Math.min(minX, s[i]); maxX = Math.max(maxX, s[i]); minY = Math.min(minY, s[i+1]); maxY = Math.max(maxY, s[i+1]); } });
    var size = Math.max(maxX - minX, maxY - minY, 1), scale = 100 / size, m = 8;
    var w = Math.ceil((maxX - minX) * scale) + 2 * m, h = Math.ceil((maxY - minY) * scale) + 2 * m;
    var px = new Array(w * h).fill(255), r2 = rr * rr;
    function stamp(cx, cy) {
        for (var y = Math.max(0, Math.floor(cy - rr)); y <= Math.min(h - 1, Math.ceil(cy + rr)); y++)
            for (var x = Math.max(0, Math.floor(cx - rr)); x <= Math.min(w - 1, Math.ceil(cx + rr)); x++) {
                var dx = x + .5 - cx, dy = y + .5 - cy; if (dx*dx + dy*dy <= r2) px[y*w+x] = 0; } }
    list.forEach(function (s) { var prev = null; for (var i = 0; i < s.length; i += 2) {
        var cx = (s[i] - minX) * scale + m, cy = (s[i+1] - minY) * scale + m;
        if (!prev) stamp(cx, cy); else { var ex = cx - prev.x, ey = cy - prev.y, n = Math.max(1, Math.ceil(Math.hypot(ex, ey) / 1.2));
            for (var t = 1; t <= n; t++) stamp(prev.x + ex*t/n, prev.y + ey*t/n); }
        prev = {x: cx, y: cy}; } });
    return {px: px, w: w, h: h};
}
var dir = path.join(__dirname, "user-samples");
var files = process.argv.length > 2 ? process.argv.slice(2) : fs.readdirSync(dir).filter(function (f) { return /\.json$/.test(f); }).map(function (f) { return path.join(dir, f); });
var tot = 0, ok = 0;
files.forEach(function (f) {
    var a = JSON.parse(fs.readFileSync(f, "utf8")), n = 0, k = 0, miss = [];
    a.forEach(function (smp) {
        var r = raster(smp.strokes, 3.25), res = R.recognize(R.preprocess(r.px, r.w, r.h));
        n++; if (res.digit === smp.label) k++; else miss.push(smp.label + "->" + res.digit + "(" + res.confidence.toFixed(2) + ")");
    });
    tot += n; ok += k;
    console.log(path.basename(f) + ": " + k + "/" + n + (miss.length ? "  misses: " + miss.join(" ") : ""));
});
console.log("TOTAL " + ok + "/" + tot);
