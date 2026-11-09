import * as spruce from "spruce";
import * as box from "spruce/box";
import * as message from "spruce/message";
import * as table from "spruce/table";
import * as style from "spruce/style";
import * as markdown from "spruce/markdown";
import * as highlight from "spruce/highlight";
import { List, Result$isOk, Result$Ok$0 } from "spruce/gleam";

const context: spruce.Spruce$ = spruce.no_color();
const green: style.Color$ = style.Color$Green();
const styled: style.Style$ = style.bold(style.fg(style.new$(), green));
const success: string = message.success(context, "Packed");
const framed: string = box.render(
  context, "Ready", box.foreground(box.new$(), green),
);
const grid: table.Table$ = table.rows(
  table.headers(table.new$(), List.fromArray(["Name"])),
  List.fromArray([List.fromArray(["Spruce"])]),
);
const rendered: string = table.render(context, grid);
const text: string = markdown.render(context, "**Native**");
const language = highlight.language("javascript");
if (Result$isOk(language)) {
  const resolved: highlight.Language$ | undefined = Result$Ok$0(language);
  if (resolved !== undefined) {
    const name: string = highlight.language_name(resolved);
    void name;
  }
}

// @ts-expect-error A number is not a Gleam String.
message.success(context, 42);
// @ts-expect-error The native context is opaque, not a plain object.
message.success({}, "Packed");
// @ts-expect-error Native lists are not JavaScript arrays.
table.headers(grid, ["Name"]);
// @ts-expect-error A nested list of numbers is not a list of string rows.
table.rows(grid, List.fromArray([List.fromArray([42])]));
// @ts-expect-error Colors are native custom types, not strings.
style.fg(styled, "green");
// @ts-expect-error A native Result is not a resolved Language.
highlight.language_name(language);
// @ts-expect-error Dependency modules are not automatic public exports.
import * as hidden from "spruce/gleam_stdlib/gleam/list";

void [success, framed, rendered, text, hidden];
