import gleam/dict
import gleam/option.{None, Some}
import gleam/package_interface.{
  type Implementations, type Module, Function, Implementations, Module,
  Parameter, TypeConstructor, TypeDefinition,
}
import gleam/string
import gleeunit/should
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
  let result = dts.emit_module(empty_module(), "test", "test_module")
  result.content |> should.equal("\n")
  result.warnings |> should.equal([])
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

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains(
    "export declare function add(a: number, b: number): number;",
  )
  |> should.be_true()
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

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains("export declare function identity<A>(value: A): A;")
  |> should.be_true()
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

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains("export interface Person")
  |> should.be_true()
  result.content
  |> string.contains("readonly name: string;")
  |> should.be_true()
  result.content
  |> string.contains("readonly age: number;")
  |> should.be_true()
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

  let result = dts.emit_module(module, "test", "test_module")
  // Check discriminated union
  result.content
  |> string.contains("export type Shape = Circle | Rectangle;")
  |> should.be_true()
  // Check $type discriminant tag
  result.content
  |> string.contains("[$type]: \"Circle\"")
  |> should.be_true()
  result.content
  |> string.contains("[$type]: \"Rectangle\"")
  |> should.be_true()
  // Check that the unique symbol declaration is included
  result.content
  |> string.contains("declare const $type: unique symbol;")
  |> should.be_true()
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

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains("export type Secret")
  |> should.be_true()
  // Should produce a warning
  result.warnings
  |> should.not_equal([])
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

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains("erlang_only")
  |> should.be_false()
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

  let result = dts.emit_module(module, "test", "test_module")
  // Reserved words should be escaped with $
  result.content
  |> string.contains("export declare function new$(name: string): string;")
  |> should.be_true()
  result.content
  |> string.contains("export declare function null$(): undefined;")
  |> should.be_true()
  // Non-reserved words should not be escaped
  result.content
  |> string.contains("export declare function safe_name(): undefined;")
  |> should.be_true()
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

  let result = dts.emit_module(module, "mylib", "mylib/main")
  // Should include import statements
  result.content
  |> string.contains("import type { Level } from \"./types.js\";")
  |> should.be_true()
  result.content
  |> string.contains("import type { Handler } from \"./util.js\";")
  |> should.be_true()
}
