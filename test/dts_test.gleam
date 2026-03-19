import gleam/dict
import gleam/option.{None, Some}
import gleam/package_interface.{
  type Implementations, type Module, Function, Implementations, Module,
  Parameter, TypeConstructor, TypeDefinition,
}
import gleam/set
import gleam/string
import startest/expect
import talc/dts

fn test_implementations() -> Implementations {
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

pub fn emit_empty_module_test() {
  let result =
    dts.emit_module(empty_module(), "test", "test_module", dict.new())
  result.content |> expect.to_equal("\n")
  result.warnings |> expect.to_equal([])
}

pub fn emit_simple_function_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "add",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [
              Parameter(
                label: Some("a"),
                type_: package_interface.Named("Int", "", "gleam", []),
              ),
              Parameter(
                label: Some("b"),
                type_: package_interface.Named("Int", "", "gleam", []),
              ),
            ],
            return: package_interface.Named("Int", "", "gleam", []),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  result.content
  |> string.contains(
    "export declare function add(a: number, b: number): number;",
  )
  |> expect.to_be_true()
}

pub fn emit_generic_function_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "identity",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [
              Parameter(
                label: Some("value"),
                type_: package_interface.Variable(1),
              ),
            ],
            return: package_interface.Variable(1),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  result.content
  |> string.contains("export declare function identity<A>(value: A): A;")
  |> expect.to_be_true()
}

pub fn emit_record_type_test() {
  let module =
    Module(
      ..empty_module(),
      types: dict.from_list([
        #(
          "Person",
          TypeDefinition(
            documentation: None,
            deprecation: None,
            parameters: 0,
            constructors: [
              TypeConstructor(documentation: None, name: "Person", parameters: [
                Parameter(
                  label: Some("name"),
                  type_: package_interface.Named("String", "", "gleam", []),
                ),
                Parameter(
                  label: Some("age"),
                  type_: package_interface.Named("Int", "", "gleam", []),
                ),
              ]),
            ],
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  result.content
  |> string.contains("export interface Person")
  |> expect.to_be_true()
  result.content
  |> string.contains("readonly name: string;")
  |> expect.to_be_true()
  result.content
  |> string.contains("readonly age: number;")
  |> expect.to_be_true()
}

pub fn emit_adt_type_test() {
  let module =
    Module(
      ..empty_module(),
      types: dict.from_list([
        #(
          "Shape",
          TypeDefinition(
            documentation: None,
            deprecation: None,
            parameters: 0,
            constructors: [
              TypeConstructor(documentation: None, name: "Circle", parameters: [
                Parameter(
                  label: Some("radius"),
                  type_: package_interface.Named("Float", "", "gleam", []),
                ),
              ]),
              TypeConstructor(
                documentation: None,
                name: "Rectangle",
                parameters: [
                  Parameter(
                    label: Some("width"),
                    type_: package_interface.Named("Float", "", "gleam", []),
                  ),
                  Parameter(
                    label: Some("height"),
                    type_: package_interface.Named("Float", "", "gleam", []),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  // Check discriminated union
  result.content
  |> string.contains("export type Shape = Circle | Rectangle;")
  |> expect.to_be_true()
  // Check $type discriminant tag
  result.content
  |> string.contains("[$type]: \"Circle\"")
  |> expect.to_be_true()
  result.content
  |> string.contains("[$type]: \"Rectangle\"")
  |> expect.to_be_true()
  // Check that the unique symbol declaration is included
  result.content
  |> string.contains("declare const $type: unique symbol;")
  |> expect.to_be_true()
}

pub fn emit_opaque_type_test() {
  let module =
    Module(
      ..empty_module(),
      types: dict.from_list([
        #(
          "Secret",
          TypeDefinition(
            documentation: None,
            deprecation: None,
            parameters: 0,
            constructors: [],
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  result.content
  |> string.contains("export type Secret")
  |> expect.to_be_true()
  // Should produce a warning
  result.warnings
  |> expect.to_not_equal([])
}

pub fn skip_non_js_function_test() {
  let erlang_only =
    Implementations(
      gleam: False,
      uses_erlang_externals: True,
      uses_javascript_externals: False,
      can_run_on_erlang: True,
      can_run_on_javascript: False,
    )

  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "erlang_only",
          Function(
            documentation: None,
            deprecation: None,
            implementations: erlang_only,
            parameters: [],
            return: package_interface.Named("Nil", "", "gleam", []),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  result.content
  |> string.contains("erlang_only")
  |> expect.to_be_false()
}

pub fn emit_reserved_word_function_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "new",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [
              Parameter(
                label: Some("name"),
                type_: package_interface.Named("String", "", "gleam", []),
              ),
            ],
            return: package_interface.Named("String", "", "gleam", []),
          ),
        ),
        #(
          "null",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [],
            return: package_interface.Named("Nil", "", "gleam", []),
          ),
        ),
        #(
          "safe_name",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [],
            return: package_interface.Named("Nil", "", "gleam", []),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", dict.new())
  // Reserved words should be escaped with $
  result.content
  |> string.contains("export declare function new$(name: string): string;")
  |> expect.to_be_true()
  result.content
  |> string.contains("export declare function null$(): undefined;")
  |> expect.to_be_true()
  // Non-reserved words should not be escaped
  result.content
  |> string.contains("export declare function safe_name(): undefined;")
  |> expect.to_be_true()
}

pub fn emit_cross_module_imports_test() {
  // Module "mylib/main" references types from "mylib/types" and "mylib/util"
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "get_level",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [],
            return: package_interface.Named("Level", "mylib", "mylib/types", []),
          ),
        ),
        #(
          "make_handler",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [
              Parameter(
                label: Some("name"),
                type_: package_interface.Named("String", "", "gleam", []),
              ),
            ],
            return: package_interface.Named(
              "Handler",
              "mylib",
              "mylib/util",
              [],
            ),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "mylib", "mylib/main", dict.new())
  // Should include import statements
  result.content
  |> string.contains("import type { Level } from \"./types.js\";")
  |> expect.to_be_true()
  result.content
  |> string.contains("import type { Handler } from \"./util.js\";")
  |> expect.to_be_true()
}

pub fn emit_external_type_map_import_test() {
  let type_maps = dict.from_list([#("gleam_json", "gleam-json")])

  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "encode",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [
              Parameter(
                label: Some("value"),
                type_: package_interface.Variable(1),
              ),
            ],
            return: package_interface.Named(
              "Json",
              "gleam_json",
              "gleam/json",
              [],
            ),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", type_maps)
  // Should include external import
  result.content
  |> string.contains("import type { Json } from \"gleam-json/gleam/json.js\";")
  |> expect.to_be_true()
  // Should use the type name, not unknown
  result.content
  |> string.contains("): Json;")
  |> expect.to_be_true()
  // No warnings for mapped types
  result.warnings |> expect.to_equal([])
}

pub fn emit_external_type_map_scoped_package_test() {
  let type_maps = dict.from_list([#("gleam_http", "@scope/gleam-http")])

  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "get",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [
              Parameter(
                label: Some("req"),
                type_: package_interface.Named(
                  "Request",
                  "gleam_http",
                  "gleam/http",
                  [],
                ),
              ),
            ],
            return: package_interface.Named("String", "", "gleam", []),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", type_maps)
  result.content
  |> string.contains(
    "import type { Request } from \"@scope/gleam-http/gleam/http.js\";",
  )
  |> expect.to_be_true()
}

pub fn emit_external_type_map_tracks_used_packages_test() {
  let type_maps =
    dict.from_list([
      #("gleam_json", "gleam-json"),
      #("gleam_http", "@scope/gleam-http"),
    ])

  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "encode",
          Function(
            documentation: None,
            deprecation: None,
            implementations: test_implementations(),
            parameters: [],
            return: package_interface.Named(
              "Json",
              "gleam_json",
              "gleam/json",
              [],
            ),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module", type_maps)
  // gleam-json should be in used packages
  result.used_type_map_packages
  |> set.contains("gleam-json")
  |> expect.to_be_true()
  // gleam-http was not used, so it should not be in used packages
  result.used_type_map_packages
  |> set.contains("@scope/gleam-http")
  |> expect.to_be_false()
}
