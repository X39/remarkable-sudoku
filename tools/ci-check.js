// CI sanity check: the shipped recognizer loads and still reads the recorded samples well.
// Fails (exit 1) if accuracy over tools/user-samples drops below MIN. Run: node tools/ci-check.js
var cp = require("child_process"), path = require("path");
var MIN = 0.85;
var out = cp.execFileSync(process.execPath, [path.join(__dirname, "eval-samples.js")], {encoding: "utf8"});
console.log(out);
var m = /TOTAL\s+(\d+)\/(\d+)/.exec(out);
if (!m) { console.error("eval-samples.js printed no TOTAL line"); process.exit(1); }
var acc = +m[1] / +m[2];
console.log("accuracy " + (acc * 100).toFixed(1) + "% (minimum " + MIN * 100 + "%)");
process.exit(acc >= MIN ? 0 : 1);
