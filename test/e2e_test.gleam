/// End-to-end test: generate a complete npm package from a synthetic Gleam
/// package interface and validate the .d.ts files with the TypeScript compiler.
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/package_interface.{
  type Module, type Package, Function, Implementations, Module, Package,
  Parameter, TypeConstructor, TypeDefinition,
}
import gleam/string
import gleeunit/should
import simplifile
import talc/dts
import talc/interface

// -- FFI --

@external(erlang, "e2e_test_ffi", "run_command")
fn run_command(cmd: String, work_dir: String) -> Result(#(Int, String), Nil)

@external(erlang, "talc_interface_ffi", "random_id")
fn random_id() -> String

// -- Helpers --

fn js_implementations() -> package_interface.Implementations {
  Implementations(
    gleam: True,
    uses_erlang_externals: False,
    uses_javascript_externals: False,
    can_run_on_erlang: True,
    can_run_on_javascript: True,
  )
}

/// Build the synthetic package covering all important patterns:
/// - ADTs (discriminated unions)
/// - Records (single constructor)
/// - Opaque types
/// - Cross-module type references
/// - Reserved word function names
/// - Option, Result, List, Dict, Tuple, Function types
/// - Generic types
fn build_test_package() -> Package {
  Package(
    name: "testlib",
    version: "1.0.0",
    gleam_version_constraint: None,
    modules: dict.from_list([
      #("testlib/types", types_module()),
      #("testlib/utils", utils_module()),
      #("testlib", main_module()),
    ]),
  )
}

fn types_module() -> Module {
  Module(
    documentation: [],
    type_aliases: dict.new(),
    constants: dict.new(),
    types: dict.from_list([
      // ADT: Color with Red, Green, Blue(intensity)
      #(
        "Color",
        TypeDefinition(
          documentation: Some(" Represents a color.\n"),
          deprecation: None,
          parameters: 0,
          constructors: [
            TypeConstructor(documentation: None, name: "Red", parameters: []),
            TypeConstructor(documentation: None, name: "Green", parameters: []),
            TypeConstructor(documentation: None, name: "Blue", parameters: [
              Parameter(
                label: Some("intensity"),
                type_: package_interface.Named("Float", "", "gleam", []),
              ),
            ]),
          ],
        ),
      ),
      // Record: Point { x: Float, y: Float }
      #(
        "Point",
        TypeDefinition(
          documentation: Some(" A 2D point.\n"),
          deprecation: None,
          parameters: 0,
          constructors: [
            TypeConstructor(documentation: None, name: "Point", parameters: [
              Parameter(
                label: Some("x"),
                type_: package_interface.Named("Float", "", "gleam", []),
              ),
              Parameter(
                label: Some("y"),
                type_: package_interface.Named("Float", "", "gleam", []),
              ),
            ]),
          ],
        ),
      ),
      // Opaque: Token
      #(
        "Token",
        TypeDefinition(
          documentation: None,
          deprecation: None,
          parameters: 0,
          constructors: [],
        ),
      ),
      // Generic ADT: Container(a) = Empty | Holding(value: a)
      #(
        "Container",
        TypeDefinition(
          documentation: None,
          deprecation: None,
          parameters: 1,
          constructors: [
            TypeConstructor(documentation: None, name: "Empty", parameters: []),
            TypeConstructor(documentation: None, name: "Holding", parameters: [
              Parameter(
                label: Some("value"),
                type_: package_interface.Variable(0),
              ),
            ]),
          ],
        ),
      ),
    ]),
    functions: dict.from_list([
      #(
        "to_string",
        Function(
          documentation: Some(" Convert a color to a string.\n"),
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("color"),
              type_: package_interface.Named(
                "Color",
                "testlib",
                "testlib/types",
                [],
              ),
            ),
          ],
          return: package_interface.Named("String", "", "gleam", []),
        ),
      ),
    ]),
  )
}

fn utils_module() -> Module {
  Module(
    documentation: [],
    type_aliases: dict.new(),
    constants: dict.new(),
    types: dict.new(),
    functions: dict.from_list([
      // Reserved word: new
      #(
        "new",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("name"),
              type_: package_interface.Named("String", "", "gleam", []),
            ),
          ],
          return: package_interface.Named(
            "Token",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
      // Option parameter
      #(
        "maybe_parse",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("input"),
              type_: package_interface.Named(
                "Option",
                "gleam_stdlib",
                "gleam/option",
                [package_interface.Named("String", "", "gleam", [])],
              ),
            ),
          ],
          return: package_interface.Named("Int", "", "gleam", []),
        ),
      ),
      // Result return
      #(
        "safe_divide",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("a"),
              type_: package_interface.Named("Float", "", "gleam", []),
            ),
            Parameter(
              label: Some("b"),
              type_: package_interface.Named("Float", "", "gleam", []),
            ),
          ],
          return: package_interface.Named("Result", "", "gleam", [
            package_interface.Named("Float", "", "gleam", []),
            package_interface.Named("String", "", "gleam", []),
          ]),
        ),
      ),
      // Generic function
      #(
        "identity",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("value"),
              type_: package_interface.Variable(1),
            ),
          ],
          return: package_interface.Variable(1),
        ),
      ),
      // Tuple return
      #(
        "swap",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("pair"),
              type_: package_interface.Tuple([
                package_interface.Variable(1),
                package_interface.Variable(2),
              ]),
            ),
          ],
          return: package_interface.Tuple([
            package_interface.Variable(2),
            package_interface.Variable(1),
          ]),
        ),
      ),
      // Function parameter (callback)
      #(
        "map_point",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("point"),
              type_: package_interface.Named(
                "Point",
                "testlib",
                "testlib/types",
                [],
              ),
            ),
            Parameter(
              label: Some("transform"),
              type_: package_interface.Fn(
                [package_interface.Named("Float", "", "gleam", [])],
                package_interface.Named("Float", "", "gleam", []),
              ),
            ),
          ],
          return: package_interface.Named(
            "Point",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
      // List parameter
      #(
        "sum",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("numbers"),
              type_: package_interface.Named("List", "", "gleam", [
                package_interface.Named("Int", "", "gleam", []),
              ]),
            ),
          ],
          return: package_interface.Named("Int", "", "gleam", []),
        ),
      ),
      // Dict parameter
      #(
        "lookup",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("dict"),
              type_: package_interface.Named(
                "Dict",
                "gleam_stdlib",
                "gleam/dict",
                [
                  package_interface.Named("String", "", "gleam", []),
                  package_interface.Named("Int", "", "gleam", []),
                ],
              ),
            ),
            Parameter(
              label: Some("key"),
              type_: package_interface.Named("String", "", "gleam", []),
            ),
          ],
          return: package_interface.Named("Result", "", "gleam", [
            package_interface.Named("Int", "", "gleam", []),
            package_interface.Named("Nil", "", "gleam", []),
          ]),
        ),
      ),
      // Reserved word: null
      #(
        "null",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [],
          return: package_interface.Named(
            "Token",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
    ]),
  )
}

fn main_module() -> Module {
  Module(
    documentation: [],
    type_aliases: dict.new(),
    constants: dict.new(),
    types: dict.new(),
    functions: dict.from_list([
      // Cross-module: returns a type from testlib/types
      #(
        "default_color",
        Function(
          documentation: Some(" Get the default color.\n"),
          deprecation: None,
          implementations: js_implementations(),
          parameters: [],
          return: package_interface.Named(
            "Color",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
      // Uses Point from testlib/types
      #(
        "origin",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [],
          return: package_interface.Named(
            "Point",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
      // Uses Container generic from testlib/types
      #(
        "wrap",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_implementations(),
          parameters: [
            Parameter(
              label: Some("value"),
              type_: package_interface.Variable(0),
            ),
          ],
          return: package_interface.Named(
            "Container",
            "testlib",
            "testlib/types",
            [package_interface.Variable(0)],
          ),
        ),
      ),
    ]),
  )
}

// -- Test TypeScript consumer content --

fn typescript_consumer() -> String {
  "// Auto-generated TypeScript consumer for e2e validation.
// This file imports the generated .d.ts declarations and exercises all type patterns.

import type { Color, Point, Token, Container, Empty, Holding } from \"./testlib/types.js\";
import { to_string } from \"./testlib/types.js\";

import {
  new$,
  null$,
  maybe_parse,
  safe_divide,
  identity,
  swap,
  map_point,
  sum,
  lookup,
} from \"./testlib/utils.js\";

import { default_color, origin, wrap } from \"./testlib.js\";

// --- Type tests ---

// ADT: Color is a discriminated union
const red: Color = {} as Color;

// Record: Point has x and y fields
const pt: Point = { x: 1.0, y: 2.0 };
const _x: number = pt.x;
const _y: number = pt.y;

// Opaque: Token is branded
const _tok: Token = {} as Token;

// Generic ADT
const empty: Container<string> = {} as Empty<string>;
const holding: Container<number> = {} as Holding<number>;
const _hval: number = holding.value;

// --- Function tests ---

// Cross-module: main module returns types from sub-modules
const color: Color = default_color();
const _o: Point = origin();
const _w: Container<string> = wrap(\"hello\");

// Reserved words are escaped with $
const _t1: Token = new$(\"abc\");
const _t2: Token = null$();

// Option maps to nullable
const _mp: number = maybe_parse(\"hello\");
const _mp2: number = maybe_parse(undefined);

// Result maps to discriminated union
const result = safe_divide(10.0, 3.0);
if (result.ok) {
  const val: number = result.value;
} else {
  const err: string = result.error;
}

// Generic identity
const _id: string = identity(\"hello\");
const _id2: number = identity(42);

// Tuple
const _swapped: readonly [string, number] = swap([42, \"hello\"] as const as readonly [number, string]);

// Function parameter (callback)
const _mapped: Point = map_point(pt, (n: number) => n * 2);

// List maps to Array
const _s: number = sum([1, 2, 3]);

// Dict maps to Map
const m = new Map<string, number>();
const _lr = lookup(m, \"key\");
if (_lr.ok) {
  const _v: number = _lr.value;
} else {
  const _e: undefined = _lr.error;
}

// to_string takes Color (cross-module reference within types module)
const _cs: string = to_string(color);
"
}

fn tsconfig_content() -> String {
  "{
  \"compilerOptions\": {
    \"strict\": true,
    \"module\": \"ESNext\",
    \"moduleResolution\": \"bundler\",
    \"target\": \"ES2022\",
    \"noEmit\": true,
    \"skipLibCheck\": false
  },
  \"include\": [\"test_consumer.ts\"]
}
"
}

// -- Main test --

pub fn e2e_typescript_validation_test() {
  let package = build_test_package()
  let tmp_dir = "/tmp/talc_e2e_" <> random_id()

  // Create output directories
  let dist_dir = tmp_dir <> "/dist"
  let assert Ok(_) = simplifile.create_directory_all(dist_dir)

  // Generate and write .d.ts files for each module
  let dts_results =
    dict.to_list(package.modules)
    |> list.map(fn(pair) {
      let #(module_name, module) = pair
      let result = dts.emit_module(module, package.name, module_name)
      let dts_path = interface.module_to_dts_path(module_name)
      #(dts_path, result)
    })

  // Write .d.ts files
  list.each(dts_results, fn(pair) {
    let #(rel_path, result) = pair
    let full_path = dist_dir <> "/" <> rel_path
    // Create parent directory
    let dir = string_before_last(full_path, "/")
    let assert Ok(_) = simplifile.create_directory_all(dir)
    let assert Ok(_) = simplifile.write(to: full_path, contents: result.content)
  })

  // Write TypeScript consumer test and tsconfig
  let assert Ok(_) =
    simplifile.write(
      to: dist_dir <> "/test_consumer.ts",
      contents: typescript_consumer(),
    )
  let assert Ok(_) =
    simplifile.write(
      to: dist_dir <> "/tsconfig.json",
      contents: tsconfig_content(),
    )

  // Install TypeScript and run tsc --noEmit
  let assert Ok(#(tsc_code, tsc_output)) =
    run_command("tsc --noEmit --project tsconfig.json", dist_dir)

  // If tsc fails, show the errors for debugging
  case tsc_code {
    0 -> Nil
    _ -> {
      // Print generated .d.ts files for debugging
      list.each(dts_results, fn(pair) {
        let #(path, result) = pair
        let _ = string.inspect(path)
        let _ = string.inspect(result.content)
        Nil
      })
      panic as {
        "tsc --noEmit failed with "
        <> int.to_string(tsc_code)
        <> ":\n"
        <> tsc_output
      }
    }
  }

  // Verify we generated the expected number of .d.ts files
  list.length(dts_results) |> should.equal(3)

  // Verify no unexpected warnings (opaque type warning for Token is expected)
  let all_warnings =
    list.flat_map(dts_results, fn(pair) { { pair.1 }.warnings })
  // We expect exactly one warning for the opaque Token type
  all_warnings
  |> list.filter(fn(w) { string.contains(w, "Opaque type") })
  |> list.length
  |> should.equal(1)

  // Clean up
  let _ = simplifile.delete_all([tmp_dir])
  Nil
}

fn string_before_last(s: String, sep: String) -> String {
  case string.split(s, sep) {
    [] -> s
    [only] -> only
    parts -> {
      let assert [_, ..rest] = list.reverse(parts)
      list.reverse(rest) |> string.join(sep)
    }
  }
}
