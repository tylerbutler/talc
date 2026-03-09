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
  let result = dts.emit_module(empty_module(), "test", "test")
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

  let result = dts.emit_module(module, "test", "test")
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

  let result = dts.emit_module(module, "test", "test")
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

  let result = dts.emit_module(module, "test", "test")
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

  let result = dts.emit_module(module, "test", "test")
  // Check union type
  result.content
  |> string.contains("export type Shape = Circle | Rectangle;")
  |> should.be_true()
  // Check class declarations
  result.content
  |> string.contains("export declare class Circle")
  |> should.be_true()
  result.content
  |> string.contains("export declare class Rectangle")
  |> should.be_true()
  // Check fields
  result.content
  |> string.contains("readonly radius: number;")
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

  let result = dts.emit_module(module, "test", "test")
  result.content
  |> string.contains("export type Secret")
  |> should.be_true()
  // Should include declare const for valid branded type
  result.content
  |> string.contains("declare const Secret: unique symbol;")
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

  let result = dts.emit_module(module, "test", "test")
  result.content
  |> string.contains("erlang_only")
  |> should.be_false()
}
