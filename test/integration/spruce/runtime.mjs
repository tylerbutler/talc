import { strict as assert } from "node:assert";
import * as spruce from "spruce";
import * as box from "spruce/box";
import * as message from "spruce/message";
import * as table from "spruce/table";
import * as style from "spruce/style";
import * as markdown from "spruce/markdown";
import * as highlight from "spruce/highlight";
import { List, Result$isOk, Result$isError, Result$Ok$0 } from "spruce/gleam";

const context = spruce.no_color();
const green = style.Color$Green();
assert.equal(style.Color$isGreen(green), true);
const boldGreen = style.bold(style.fg(style.new$(), green));
assert.equal(style.render(context, boldGreen, "Ready"), "Ready");
assert.equal(message.success(context, "Packed"), "\u2714 success Packed");
assert.equal(
  box.render(context, "Ready", box.foreground(box.new$(), green)),
  "\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e\n"
    + "\u2502 Ready \u2502\n"
    + "\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f",
);

let grid = table.headers(table.new$(), List.fromArray(["Name", "Lang"]));
grid = table.rows(grid, List.fromArray([
  List.fromArray(["Spruce", "Gleam"]),
  List.fromArray(["Box", "UI"]),
]));
grid = table.style_fn(grid, (row, column) => {
  assert.equal(Number.isInteger(column), true);
  assert.equal(
    table.RowContext$isHeader(row) || table.RowContext$isBody(row), true,
  );
  return boldGreen;
});
assert.equal(table.render(context, grid), [
  "\u250c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u252c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510",
  "\u2502 Name   \u2502 Lang  \u2502",
  "\u251c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u253c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2524",
  "\u2502 Spruce \u2502 Gleam \u2502",
  "\u2502 Box    \u2502 UI    \u2502",
  "\u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2534\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518",
].join("\n"));

assert.equal(
  markdown.render(context, "# Ready\n\n**Native** package.\n"),
  "# Ready\n\nNative package.",
);
const language = highlight.language("js");
assert.equal(Result$isOk(language), true);
assert.equal(highlight.language_name(Result$Ok$0(language)), "javascript");
assert.equal(Result$isError(highlight.language("not-a-language")), true);
const code = "const answer = 42;";
const colored = highlight.highlight(
  spruce.with_color_level(spruce.ColorLevel$TrueColor()), code, "javascript",
);
assert.match(colored, /\u001b\[/);
assert.equal(colored.replace(/\u001b\[[0-9;]*m/g, ""), code);
const fenced = markdown.render(
  spruce.with_color_level(spruce.ColorLevel$TrueColor()),
  "```javascript\nconst answer = 42;\n```",
);
assert.match(fenced, /\u001b\[/);
assert.match(fenced.replace(/\u001b\[[0-9;]*m/g, ""), /const answer = 42;/);

for (const hidden of [
  "spruce/gleam_stdlib/gleam/list",
  "spruce/tty",
  "spruce/mork",
  "spruce/smalto",
  "spruce/dist/spruce.mjs",
  "spruce/prelude.mjs",
]) {
  await assert.rejects(import(hidden), { code: "ERR_PACKAGE_PATH_NOT_EXPORTED" });
}
assert.equal("Spruce$Spruce" in spruce, false, "opaque constructor stays private");
console.log("PASS installed native rendering, collections, transitive paths, hidden exports");
