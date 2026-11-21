// Handwritten digit recognizer (1-9) for the Sudoku app. ES5 only.
// NOTE: preprocess() expects BLACK ink on WHITE paper (grey 0..255); it inverts
// to white-on-black (MNIST style). recognize() expects the 784 values it returns.
// Must stay identical to preprocess() in tools/train_digit.py.
// Usage from QML: import "digit-recognizer.js" as Recognizer
//   Recognizer.recognize(Recognizer.preprocess(pixels, w, h))
.pragma library
.import "digit-model.js" as ModelLib

var THRESH = 0.1;

function rnd(x) {
    return Math.floor(x + 0.5);
}

// dst x src matrix (array of rows) of exact box-filter coverage weights.
function resizeMatrix(src, dst) {
    var r = src / dst;
    var m = [];
    for (var i = 0; i < dst; i++) {
        var row = [];
        for (var k = 0; k < src; k++) row.push(0);
        var a = i * r, b = (i + 1) * r;
        var jEnd = Math.min(src, Math.ceil(b));
        for (var j = Math.floor(a); j < jEnd; j++) {
            row[j] = (Math.min(b, j + 1) - Math.max(a, j)) / r;
        }
        m.push(row);
    }
    return m;
}

// pixels: flat array, grey 0..255, black ink on white paper, length width*height.
// Returns array of 784 floats 0..1, white ink on black, bbox scaled to 20 px
// and centred by centre of mass in 28x28.
function preprocess(pixels, width, height) {
    var out = [];
    var i, x, y;
    for (i = 0; i < 784; i++) out.push(0);
    var minX = width, maxX = -1, minY = height, maxY = -1;
    var inv = [];
    for (i = 0; i < width * height; i++) inv.push((255 - pixels[i]) / 255);
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            if (inv[y * width + x] > THRESH) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    if (maxX < 0) return out;
    var w = maxX - minX + 1, h = maxY - minY + 1;
    var s = 20 / Math.max(h, w);
    var nh = Math.max(1, rnd(h * s)), nw = Math.max(1, rnd(w * s));
    var my = resizeMatrix(h, nh), mx = resizeMatrix(w, nw);
    // tmp = my * crop  (nh x w)
    var tmp = [];
    var a, b, acc;
    for (a = 0; a < nh; a++) {
        var trow = [];
        for (x = 0; x < w; x++) {
            acc = 0;
            for (y = 0; y < h; y++) {
                var wy = my[a][y];
                if (wy !== 0) acc += wy * inv[(minY + y) * width + minX + x];
            }
            trow.push(acc);
        }
        tmp.push(trow);
    }
    var oy = Math.floor((28 - nh) / 2), ox = Math.floor((28 - nw) / 2);
    var canvas = [];
    for (i = 0; i < 784; i++) canvas.push(0);
    for (a = 0; a < nh; a++) {
        for (b = 0; b < nw; b++) {
            acc = 0;
            for (x = 0; x < w; x++) {
                var wx = mx[b][x];
                if (wx !== 0) acc += wx * tmp[a][x];
            }
            canvas[(oy + a) * 28 + ox + b] = acc;
        }
    }
    var tot = 0, sy = 0, sx = 0;
    for (y = 0; y < 28; y++) {
        for (x = 0; x < 28; x++) {
            var v = canvas[y * 28 + x];
            tot += v;
            sy += v * y;
            sx += v * x;
        }
    }
    if (tot <= 0) return out;
    var dy = rnd(14 - sy / tot), dx = rnd(14 - sx / tot);
    for (y = 0; y < 28; y++) {
        var ty = y + dy;
        if (ty < 0 || ty >= 28) continue;
        for (x = 0; x < 28; x++) {
            var tx = x + dx;
            if (tx < 0 || tx >= 28) continue;
            out[ty * 28 + tx] = canvas[y * 28 + x];
        }
    }
    return out;
}

// input784: array of 784 floats 0..1 (white on black), e.g. from preprocess().
// Returns {digit: 1..9, confidence: 0..1, scores: [9 probabilities for 1..9]}.
// ReLU(valid 3x3 convolution) followed by 2x2 max pooling (floor), channel-major flat arrays.
function convPool(inp, ic, iw, w, b, oc) {
    var ow = iw - 2, pw = Math.floor(ow / 2);
    var out = new Array(oc * pw * pw);
    var o, c, y, x, ky, kx, acc, best, v;
    var plane = ow * ow;
    var conv = new Array(plane);
    for (o = 0; o < oc; o++) {
        for (y = 0; y < ow; y++) {
            for (x = 0; x < ow; x++) {
                acc = b[o];
                for (c = 0; c < ic; c++) {
                    var wb = (o * ic + c) * 9, ib = c * iw * iw;
                    for (ky = 0; ky < 3; ky++) {
                        var ir = ib + (y + ky) * iw + x;
                        var wr = wb + ky * 3;
                        v = inp[ir];     if (v !== 0) acc += v * w[wr];
                        v = inp[ir + 1]; if (v !== 0) acc += v * w[wr + 1];
                        v = inp[ir + 2]; if (v !== 0) acc += v * w[wr + 2];
                    }
                }
                conv[y * ow + x] = acc > 0 ? acc : 0;
            }
        }
        for (y = 0; y < pw; y++) {
            for (x = 0; x < pw; x++) {
                var r0 = 2 * y * ow + 2 * x;
                best = conv[r0];
                if (conv[r0 + 1] > best) best = conv[r0 + 1];
                if (conv[r0 + ow] > best) best = conv[r0 + ow];
                if (conv[r0 + ow + 1] > best) best = conv[r0 + ow + 1];
                out[(o * pw + y) * pw + x] = best;
            }
        }
    }
    return out;
}

// Raw 10 logits for a 28x28 (784 floats, white-on-black) input, for the CNN or the old MLP model.
function logits(input784) {
    var m = ModelLib.DigitModel;
    var j, i, k, s;
    var z = [];
    if (m.kind === "cnn") {
        var f1 = convPool(input784, 1, 28, m.w1, m.b1, m.c1);        // c1 x 13 x 13
        var f2 = convPool(f1, m.c1, 13, m.w2, m.b2, m.c2);           // c2 x 5 x 5
        var n = m.c2 * 25, h = [];
        for (j = 0; j < m.fc; j++) {
            s = m.b3[j];
            var wb = j * n;
            for (i = 0; i < n; i++) { if (f2[i] !== 0) s += f2[i] * m.w3[wb + i]; }
            h.push(s > 0 ? s : 0);
        }
        for (k = 0; k < 10; k++) {
            s = m.b4[k];
            for (j = 0; j < m.fc; j++) { if (h[j] !== 0) s += h[j] * m.w4[k * m.fc + j]; }
            z.push(s);
        }
        return z;
    }
    var H = m.hidden;
    var hh = [];
    for (j = 0; j < H; j++) hh.push(m.b1[j]);
    for (i = 0; i < 784; i++) {
        var v = input784[i];
        if (v === 0) continue;
        var base = i * H;
        for (j = 0; j < H; j++) hh[j] += v * m.W1[base + j];
    }
    for (k = 0; k < 10; k++) {
        s = m.b2[k];
        for (j = 0; j < H; j++) {
            if (hh[j] > 0) s += hh[j] * m.W2[j * 10 + k];
        }
        z.push(s);
    }
    return z;
}

function recognize(input784) {
    var z = logits(input784);
    var k, mx = -1e30;
    for (k = 0; k < 10; k++) if (z[k] > mx) mx = z[k];
    var e = [], sum = 0;
    for (k = 0; k < 10; k++) {
        e.push(Math.exp(z[k] - mx));
        sum += e[k];
    }
    // softmax over 10 outputs, then renormalise over classes 1..9
    var sum9 = sum - e[0];
    var scores = [], best = 0;
    for (k = 1; k < 10; k++) {
        scores.push(e[k] / sum9);
        if (e[k] > e[best + 1]) best = k - 1;
    }
    return {digit: best + 1, confidence: scores[best], scores: scores};
}

// Sudoku-rule tie-break. res = recognize() result. If the best read is at least `sure` confident it
// is taken as is. Otherwise the candidates (score >= floor) are tried best first and the first one
// that does not conflict (conflicts(d) === true means the digit clashes with the board) wins; if all
// clash, the best read stays. Returns {digit, confidence, tie: true when the choice differs from the best}.
function pickDigit(res, conflicts, sure, floor) {
    if (res.confidence >= sure) return {digit: res.digit, confidence: res.confidence, tie: false};
    var order = [];
    for (var k = 0; k < res.scores.length; k++) if (res.scores[k] >= floor) order.push(k);
    order.sort(function (a, b) { return res.scores[b] - res.scores[a]; });
    for (var i = 0; i < order.length; i++) {
        var d = order[i] + 1;
        if (!conflicts(d)) return {digit: d, confidence: res.scores[order[i]], tie: d !== res.digit};
    }
    return {digit: res.digit, confidence: res.confidence, tie: false};
}
