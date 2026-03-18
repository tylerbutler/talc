import gleam/dict
import gleam/option.{None, Some}
import gleam/package_interface.{
  type Implementations, type Module, Function, Implementations, Module,
  Parameter, TypeConstructor, TypeDefinition,
}
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
  let result = dts.emit_module(empty_module(), "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "test", "test_module")
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

  let result = dts.emit_module(module, "mylib", "mylib/main")
  // Should include import statements
  result.content
  |> string.contains("import type { Level } from \"./types.js\";")
  |> expect.to_be_true()
  result.content
  |> string.contains("import type { Handler } from \"./util.js\";")
  |> expect.to_be_true()
}

pub fn emit_function_with_single_line_doc_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "add",
          Function(
            documentation: Some("Adds two integers together."),
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
  |> string.contains("/** Adds two integers together. */\n")
  |> expect.to_be_true()
  result.content
  |> string.contains(
    "export declare function add(a: number, b: number): number;",
  )
  |> expect.to_be_true()
}

pub fn emit_function_with_multi_line_doc_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "greet",
          Function(
            documentation: Some("Greets a person.\nReturns a friendly message."),
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
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains(
    "/**\n * Greets a person.\n * Returns a friendly message.\n */\n",
  )
  |> expect.to_be_true()
}

pub fn emit_record_type_with_doc_test() {
  let module =
    Module(
      ..empty_module(),
      types: dict.from_list([
        #(
          "Person",
          TypeDefinition(
            documentation: Some("Represents a person with a name and age."),
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
  |> string.contains(
    "/** Represents a person with a name and age. */\nexport interface Person",
  )
  |> expect.to_be_true()
}

pub fn emit_adt_type_with_docs_test() {
  let module =
    Module(
      ..empty_module(),
      types: dict.from_list([
        #(
          "Shape",
          TypeDefinition(
            documentation: Some("A geometric shape."),
            deprecation: None,
            parameters: 0,
            constructors: [
              TypeConstructor(
                documentation: Some("A circle with a radius."),
                name: "Circle",
                parameters: [
                  Parameter(
                    label: Some("radius"),
                    type_: package_interface.Named("Float", "", "gleam", []),
                  ),
                ],
              ),
              TypeConstructor(
                documentation: Some("A rectangle with width and height."),
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
  // Constructor-level docs
  result.content
  |> string.contains("/** A circle with a radius. */\nexport interface Circle")
  |> expect.to_be_true()
  result.content
  |> string.contains(
    "/** A rectangle with width and height. */\nexport interface Rectangle",
  )
  |> expect.to_be_true()
  // Type-level doc on the union
  result.content
  |> string.contains("/** A geometric shape. */\nexport type Shape")
  |> expect.to_be_true()
}

pub fn emit_opaque_type_with_doc_test() {
  let module =
    Module(
      ..empty_module(),
      types: dict.from_list([
        #(
          "Secret",
          TypeDefinition(
            documentation: Some("An opaque secret value."),
            deprecation: None,
            parameters: 0,
            constructors: [],
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module")
  result.content
  |> string.contains("/** An opaque secret value. */\nexport type Secret")
  |> expect.to_be_true()
}

pub fn emit_no_doc_when_none_test() {
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
            parameters: [],
            return: package_interface.Named("Nil", "", "gleam", []),
          ),
        ),
      ]),
    )

  let result = dts.emit_module(module, "test", "test_module")
  // Should not contain any JSDoc
  result.content
  |> string.contains("/**")
  |> expect.to_be_false()
}
