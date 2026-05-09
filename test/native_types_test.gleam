import gleam/dict
import simplifile
import startest/expect
import talc/native_types.{
  NativeFunctionSignature, NativeImport, NativeModuleTypes, ReadError,
}

const declaration = "import type * as _ from \"./gleam.d.mts\";
import type { Thing as Thing$ } from \"./thing.d.mts\";

export function parse(x: Thing$<number>): _.Result<Thing$<number>, string>;
"

pub fn parse_collects_imports_test() {
  let NativeModuleTypes(imports:, functions: _) =
    native_types.parse(declaration)

  imports
  |> expect.to_equal([
    NativeImport(
      line: "import type * as _ from \"./gleam.d.mts\";",
      specifier: "./gleam.d.mts",
    ),
    NativeImport(
      line: "import type { Thing as Thing$ } from \"./thing.d.mts\";",
      specifier: "./thing.d.mts",
    ),
  ])
}

pub fn parse_collects_native_function_signatures_test() {
  let NativeModuleTypes(imports: _, functions:) =
    native_types.parse(declaration)

  dict.get(functions, "parse")
  |> expect.to_equal(
    Ok(NativeFunctionSignature(
      parameters: [#("x", "Thing$<number>")],
      return_type: "_.Result<Thing$<number>, string>",
    )),
  )
}

pub fn parse_collects_multiline_native_function_signatures_test() {
  let content =
    "export function keep_thing(thing: Thing$<number>): _.Result<
  Thing$<number>,
  string
>;"
  let NativeModuleTypes(imports: _, functions:) = native_types.parse(content)

  dict.get(functions, "keep_thing")
  |> expect.to_equal(
    Ok(NativeFunctionSignature(
      parameters: [#("thing", "Thing$<number>")],
      return_type: "_.Result< Thing$<number>, string >",
    )),
  )
}

pub fn parse_generic_function_uses_base_name_as_key_test() {
  let content = "export function identity<A>(x: A): A;"
  let NativeModuleTypes(imports: _, functions:) = native_types.parse(content)

  dict.get(functions, "identity")
  |> expect.to_equal(
    Ok(NativeFunctionSignature(parameters: [#("x", "A")], return_type: "A")),
  )
}

pub fn parse_splits_balanced_nested_parameters_test() {
  let content =
    "export function nested(pair: readonly [_.Result<Thing$<number>, string>, string], values: ReadonlyArray<Thing$<_.Result<number, string>>>): _.Result<readonly [number, string], string>;"
  let NativeModuleTypes(imports: _, functions:) = native_types.parse(content)

  dict.get(functions, "nested")
  |> expect.to_equal(
    Ok(NativeFunctionSignature(
      parameters: [
        #("pair", "readonly [_.Result<Thing$<number>, string>, string]"),
        #("values", "ReadonlyArray<Thing$<_.Result<number, string>>>"),
      ],
      return_type: "_.Result<readonly [number, string], string>",
    )),
  )
}

pub fn parse_keeps_function_arrows_inside_generic_arguments_test() {
  let content =
    "export function callbacks(x: _.Result<(a: A) => B, C>, y: string): _.Result<(value: Thing$<number>) => string, string>;"
  let NativeModuleTypes(imports: _, functions:) = native_types.parse(content)

  dict.get(functions, "callbacks")
  |> expect.to_equal(
    Ok(NativeFunctionSignature(
      parameters: [
        #("x", "_.Result<(a: A) => B, C>"),
        #("y", "string"),
      ],
      return_type: "_.Result<(value: Thing$<number>) => string, string>",
    )),
  )
}

pub fn parse_skips_function_when_parameter_is_malformed_test() {
  let content = "export function broken(valid: string, malformed): string;"
  let NativeModuleTypes(imports: _, functions:) = native_types.parse(content)

  dict.get(functions, "broken")
  |> expect.to_equal(Error(Nil))
}

pub fn read_module_reads_nested_declaration_test() {
  let package_name = "talc_native_types_test_pkg_read_module"
  let package_dir = "build/dev/javascript/" <> package_name
  let dir = package_dir <> "/native"
  let path = dir <> "/sample.d.mts"
  let _ = simplifile.create_directory_all(dir) |> expect.to_be_ok()
  let _ = simplifile.write(to: path, contents: declaration) |> expect.to_be_ok()

  let result = native_types.read_module(package_name, "native/sample")

  let _ = simplifile.delete(path) |> expect.to_be_ok()
  let _ = simplifile.delete(dir) |> expect.to_be_ok()
  let _ = simplifile.delete(package_dir) |> expect.to_be_ok()
  let _ = result |> expect.to_be_ok()
  Nil
}

pub fn read_module_preserves_read_errors_test() {
  native_types.read_module("talc", "missing/native")
  |> expect.to_equal(
    Error(ReadError(
      path: "build/dev/javascript/talc/missing/native.d.mts",
      detail: "file not found",
    )),
  )
}
