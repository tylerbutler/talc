import gleam/dict
import gleam/option.{None}
import gleam/package_interface.{
  type Implementations, type Module, Function, Implementations, Module, Named,
}
import gleam/string
import simplifile
import startest/expect
import talc/wrapper_metadata

const native_declaration = "import type { Thing } from \"./other.d.mts\";
export function load_thing(): Result<Thing<number>, string>;
"

fn js_impl() -> Implementations {
  Implementations(
    gleam: True,
    uses_erlang_externals: False,
    uses_javascript_externals: False,
    can_run_on_erlang: True,
    can_run_on_javascript: True,
  )
}

fn wrapped_module() -> Module {
  Module(
    documentation: [],
    type_aliases: dict.new(),
    types: dict.new(),
    constants: dict.new(),
    functions: dict.from_list([
      #(
        "load_thing",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
          parameters: [],
          return: result_type(thing_type(), string_type()),
        ),
      ),
    ]),
  )
}

fn unwrapped_module() -> Module {
  Module(
    documentation: [],
    type_aliases: dict.new(),
    types: dict.new(),
    constants: dict.new(),
    functions: dict.from_list([
      #(
        "name",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
          parameters: [],
          return: string_type(),
        ),
      ),
    ]),
  )
}

fn result_type(ok: package_interface.Type, err: package_interface.Type) {
  Named(name: "Result", package: "", module: "gleam", parameters: [ok, err])
}

fn string_type() {
  Named(name: "String", package: "", module: "gleam", parameters: [])
}

fn int_type() {
  Named(name: "Int", package: "", module: "gleam", parameters: [])
}

fn thing_type() {
  Named(name: "Thing", package: "other_pkg", module: "other/pkg", parameters: [
    int_type(),
  ])
}

pub fn wrapper_metadata_uses_native_declaration_test() {
  let package_name = "talc_generate_native_test_pkg"
  let package_dir = "build/dev/javascript/" <> package_name
  let path = package_dir <> "/my_lib.d.mts"
  let _ = simplifile.create_directory_all(package_dir) |> expect.to_be_ok()
  let _ =
    simplifile.write(to: path, contents: native_declaration)
    |> expect.to_be_ok()

  let #(result, warnings) =
    wrapper_metadata.generate_module_wrapper_with_metadata(
      package_name,
      "my_lib",
      wrapped_module(),
    )

  let _ = simplifile.delete(path) |> expect.to_be_ok()
  let _ = simplifile.delete(package_dir) |> expect.to_be_ok()
  warnings |> expect.to_equal([])
  result.dts
  |> string_contains("Result<Thing<number>, string>")
  |> expect.to_be_true()
}

pub fn wrapper_metadata_missing_native_warns_and_falls_back_test() {
  let #(result, warnings) =
    wrapper_metadata.generate_module_wrapper_with_metadata(
      "talc_generate_missing_test_pkg",
      "my_lib",
      wrapped_module(),
    )

  warnings
  |> expect.to_equal([
    "Missing native TypeScript metadata for module my_lib at build/dev/javascript/talc_generate_missing_test_pkg/my_lib.d.mts: file not found; falling back to generated types",
  ])
  result.warnings |> expect.to_equal(warnings)
  result.dts
  |> string_contains("Result<Thing<number>, string>")
  |> expect.to_be_true()
}

pub fn wrapper_metadata_unwrapped_missing_native_does_not_warn_test() {
  let #(result, warnings) =
    wrapper_metadata.generate_module_wrapper_with_metadata(
      "talc_generate_unwrapped_missing_test_pkg",
      "my_lib",
      unwrapped_module(),
    )

  result.has_wrapped_functions |> expect.to_be_false()
  warnings |> expect.to_equal([])
  result.warnings |> expect.to_equal([])
}

pub fn wrapper_metadata_includes_wrapper_warnings_test() {
  let package_name = "talc_generate_wrapper_warning_test_pkg"
  let package_dir = "build/dev/javascript/" <> package_name
  let path = package_dir <> "/my_lib.d.mts"
  let _ = simplifile.create_directory_all(package_dir) |> expect.to_be_ok()
  let _ = simplifile.write(to: path, contents: "") |> expect.to_be_ok()

  let #(result, warnings) =
    wrapper_metadata.generate_module_wrapper_with_metadata(
      package_name,
      "my_lib",
      wrapped_module(),
    )

  let _ = simplifile.delete(path) |> expect.to_be_ok()
  let _ = simplifile.delete(package_dir) |> expect.to_be_ok()
  warnings
  |> expect.to_equal([
    "Missing native TypeScript signature for wrapped function load_thing; falling back to generated types",
  ])
  result.warnings |> expect.to_equal(warnings)
}

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
