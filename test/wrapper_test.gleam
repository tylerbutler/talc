import gleam/dict
import gleam/option.{None, Some}
import gleam/set
import gleam/package_interface.{
  type Implementations, type Module, Function, Implementations, Module, Named,
  Parameter, Variable,
}
import gleam/string
import startest/expect
import talc/wrapper

fn js_impl() -> Implementations {
  Implementations(
    gleam: True,
    uses_erlang_externals: False,
    uses_javascript_externals: False,
    can_run_on_erlang: True,
    can_run_on_javascript: True,
  )
}

fn empty_module() -> Module {
  Module(
    documentation: [],
    type_aliases: dict.new(),
    types: dict.new(),
    constants: dict.new(),
    functions: dict.new(),
  )
}

fn result_type(ok: package_interface.Type, err: package_interface.Type) {
  Named(name: "Result", package: "", module: "gleam", parameters: [ok, err])
}

fn option_type(inner: package_interface.Type) {
  Named(
    name: "Option",
    package: "gleam_stdlib",
    module: "gleam/option",
    parameters: [inner],
  )
}

fn int_type() {
  Named(name: "Int", package: "", module: "gleam", parameters: [])
}

fn string_type() {
  Named(name: "String", package: "", module: "gleam", parameters: [])
}

fn nil_type() {
  Named(name: "Nil", package: "", module: "gleam", parameters: [])
}

// -- Tests --

pub fn passthrough_function_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "greet",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("name"), type_: string_type()),
            ],
            return: string_type(),
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_false()
  // Both mjs and dts should just re-export
  result.mjs |> string_contains("export { greet }") |> expect.to_be_true()
  result.dts |> string_contains("export { greet }") |> expect.to_be_true()
}

pub fn wrap_result_return_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "parse_int",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("s"), type_: string_type()),
            ],
            return: result_type(int_type(), nil_type()),
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_true()

  // .mjs should import Ok, Error and true-myth converters
  result.mjs |> string_contains("import { Ok, Error }") |> expect.to_be_true()
  result.mjs
  |> string_contains("import { ok, err } from \"true-myth/result\"")
  |> expect.to_be_true()
  // Should convert return value
  result.mjs
  |> string_contains("_r instanceof Ok ? ok(_r[0]) : err(_r[0])")
  |> expect.to_be_true()

  // .d.ts should use true-myth Result type
  result.dts
  |> string_contains("import type { Result } from \"true-myth/result\"")
  |> expect.to_be_true()
  result.dts
  |> string_contains("export declare function parse_int")
  |> expect.to_be_true()
  result.dts
  |> string_contains("Result<number, undefined>")
  |> expect.to_be_true()
}

pub fn wrap_option_return_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "find",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("key"), type_: string_type()),
            ],
            return: option_type(int_type()),
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_true()

  // .mjs should use Some check
  result.mjs |> string_contains("import { Some }") |> expect.to_be_true()
  result.mjs
  |> string_contains("import { just, nothing } from \"true-myth/maybe\"")
  |> expect.to_be_true()
  result.mjs
  |> string_contains("_r instanceof Some ? just(_r[0]) : nothing()")
  |> expect.to_be_true()

  // .d.ts should use Maybe type
  result.dts
  |> string_contains("import type { Maybe } from \"true-myth/maybe\"")
  |> expect.to_be_true()
  result.dts |> string_contains("Maybe<number>") |> expect.to_be_true()
}

pub fn mixed_passthrough_and_wrapped_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "add",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("a"), type_: int_type()),
              Parameter(label: Some("b"), type_: int_type()),
            ],
            return: int_type(),
          ),
        ),
        #(
          "safe_divide",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("a"), type_: int_type()),
              Parameter(label: Some("b"), type_: int_type()),
            ],
            return: result_type(int_type(), string_type()),
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_true()
  // add should be re-exported
  result.mjs |> string_contains("export { add }") |> expect.to_be_true()
  // safe_divide should be wrapped
  result.mjs
  |> string_contains("export function safe_divide")
  |> expect.to_be_true()
}

pub fn generic_result_return_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "try_map",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("value"), type_: Variable(id: 1)),
            ],
            return: result_type(Variable(id: 1), Variable(id: 2)),
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_true()
  // .d.ts should have generic params
  result.dts |> string_contains("<A, B>") |> expect.to_be_true()
  result.dts |> string_contains("Result<A, B>") |> expect.to_be_true()
}

pub fn no_wrapping_for_non_toplevel_result_test() {
  let list_of_result =
    Named(name: "List", package: "", module: "gleam", parameters: [
      result_type(int_type(), string_type()),
    ])
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "batch",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [],
            return: list_of_result,
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  // List(Result(...)) should NOT trigger wrapping — only top-level
  result.has_wrapped_functions |> expect.to_be_false()
}

pub fn prelude_type_import_test() {
  let list_type =
    Named(name: "List", package: "", module: "gleam", parameters: [
      string_type(),
    ])
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "find_in_list",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("items"), type_: list_type),
              Parameter(label: Some("key"), type_: string_type()),
            ],
            return: option_type(string_type()),
          ),
        ),
      ]),
    )

  let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_true()
  // .d.ts should import List from gleam prelude
  result.dts
  |> string_contains("import type { List } from \"../gleam.d.mts\"")
  |> expect.to_be_true()
  result.dts |> string_contains("List<string>") |> expect.to_be_true()
}

pub fn external_type_emits_unknown_test() {
  let json_type =
    Named(
      name: "Json",
      package: "gleam_json",
      module: "gleam/json",
      parameters: [],
    )
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "encode",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("value"), type_: string_type()),
            ],
            return: result_type(json_type, nil_type()),
          ),
        ),
      ]),
    )

  let result =
    wrapper.generate_module_wrapper(module, "my_lib", set.new())
  result.has_wrapped_functions |> expect.to_be_true()
  result.dts |> string_contains("Result<unknown, undefined>") |> expect.to_be_true()
}

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
