import { strict as assert } from "node:assert";
import * as spruce from "spruce";

assert.equal(process.stdout.isTTY, undefined);
assert.equal(process.stderr.isTTY, undefined);
const expected = process.argv[2];
const predicate = expected === "truecolor"
  ? spruce.ColorLevel$isTrueColor
  : spruce.ColorLevel$isNoColor;
for (const context of [
  spruce.detect(),
  spruce.detect_stream(spruce.Stream$Stdout()),
  spruce.detect_stream(spruce.Stream$Stderr()),
]) {
  assert.equal(predicate(spruce.color_level(context)), true);
  assert.equal(spruce.supports_color(context), expected === "truecolor");
}
console.log(JSON.stringify({
  expected, stdoutIsTTY: false, stderrIsTTY: false,
  NO_COLOR: process.env.NO_COLOR ?? null,
  FORCE_COLOR: process.env.FORCE_COLOR ?? null,
  TERM: process.env.TERM,
}));
