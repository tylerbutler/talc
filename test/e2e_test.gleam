/// End-to-end TypeScript validation tests.
///
/// Each test generates .d.ts files from a synthetic package interface,
/// writes a TypeScript consumer that exercises the specific pattern,
/// and runs `tsc --noEmit` to verify the declarations are valid.
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/package_interface.{
  type Module, type Package, Function, Implementations, Module, Package,
  Parameter, TypeConstructor, TypeDefinition,
}
import gleam/string
import simplifile
import startest/expect
import talc/dts
import talc/interface

// -- FFI --

@external(erlang, "e2e_test_ffi", "run_command")
fn run_command(cmd: String, work_dir: String) -> Result(#(Int, String), Nil)

@external(erlang, "talc_interface_ffi", "random_id")
fn random_id() -> String

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

fn js_impl() -> package_interface.Implementations {
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

fn tsconfig() -> String {
  "{
  \"compilerOptions\": {
    \"strict\": true,
    \"module\": \"ESNext\",
    \"moduleResolution\": \"bundler\",
    \"target\": \"ES2022\",
    \"noEmit\": true,
    \"skipLibCheck\": false
  },
  \"include\": [\"test.ts\"]
}
"
}

/// Generate .d.ts files for a package, write a TS consumer, run tsc.
/// Panics with tsc output on failure so the test runner shows the error.
fn assert_tsc_validates(package: Package, ts_consumer: String) -> Nil {
  let tmp_dir = "/tmp/talc_e2e_" <> random_id()
  let dist_dir = tmp_dir <> "/dist"
  let assert Ok(_) = simplifile.create_directory_all(dist_dir)

  // Generate and write .d.ts files
  dict.to_list(package.modules)
  |> list.each(fn(pair) {
    let #(module_name, module) = pair
    let result = dts.emit_module(module, package.name, module_name)
    let full_path = dist_dir <> "/" <> interface.module_to_dts_path(module_name)
    let dir = string_before_last(full_path, "/")
    let assert Ok(_) = simplifile.create_directory_all(dir)
    let assert Ok(_) = simplifile.write(to: full_path, contents: result.content)
  })

  // Write consumer and tsconfig
  let assert Ok(_) =
    simplifile.write(to: dist_dir <> "/test.ts", contents: ts_consumer)
  let assert Ok(_) =
    simplifile.write(to: dist_dir <> "/tsconfig.json", contents: tsconfig())

  // Run tsc
  let assert Ok(#(code, output)) =
    run_command("tsc --noEmit --project tsconfig.json", dist_dir)

  // Clean up before asserting
  let _ = simplifile.delete_all([tmp_dir])

  case code {
    0 -> Nil
    _ -> panic as { "tsc --noEmit failed:\n" <> output }
  }
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

// ---------------------------------------------------------------------------
// Test: ADTs generate valid discriminated unions
// ---------------------------------------------------------------------------

pub fn e2e_adt_discriminated_union_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg/color",
          Module(
            ..empty_module(),
            types: dict.from_list([
              #(
                "Color",
                TypeDefinition(
                  documentation: None,
                  deprecation: None,
                  parameters: 0,
                  constructors: [
                    TypeConstructor(
                      documentation: None,
                      name: "Red",
                      parameters: [],
                    ),
                    TypeConstructor(
                      documentation: None,
                      name: "Green",
                      parameters: [],
                    ),
                    TypeConstructor(
                      documentation: None,
                      name: "Blue",
                      parameters: [
                        Parameter(
                          label: Some("intensity"),
                          type_: package_interface.Named(
                            "Float",
                            "",
                            "gleam",
                            [],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import type { Color, Red, Green, Blue } from \"./pkg/color.js\";

const r: Color = {} as Red;
const g: Color = {} as Green;
const b: Color = {} as Blue;
const intensity: number = ({} as Blue).intensity;
",
  )
}

// ---------------------------------------------------------------------------
// Test: Records generate valid interfaces
// ---------------------------------------------------------------------------

pub fn e2e_record_interface_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg/geo",
          Module(
            ..empty_module(),
            types: dict.from_list([
              #(
                "Point",
                TypeDefinition(
                  documentation: None,
                  deprecation: None,
                  parameters: 0,
                  constructors: [
                    TypeConstructor(
                      documentation: None,
                      name: "Point",
                      parameters: [
                        Parameter(
                          label: Some("x"),
                          type_: package_interface.Named(
                            "Float",
                            "",
                            "gleam",
                            [],
                          ),
                        ),
                        Parameter(
                          label: Some("y"),
                          type_: package_interface.Named(
                            "Float",
                            "",
                            "gleam",
                            [],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import type { Point } from \"./pkg/geo.js\";

const pt: Point = { x: 1.0, y: 2.0 };
const _x: number = pt.x;
const _y: number = pt.y;
",
  )
}

// ---------------------------------------------------------------------------
// Test: Opaque types generate valid branded types
// ---------------------------------------------------------------------------

pub fn e2e_opaque_branded_type_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg/auth",
          Module(
            ..empty_module(),
            types: dict.from_list([
              #(
                "Token",
                TypeDefinition(
                  documentation: None,
                  deprecation: None,
                  parameters: 0,
                  constructors: [],
                ),
              ),
            ]),
            functions: dict.from_list([
              #(
                "validate",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [
                    Parameter(
                      label: Some("token"),
                      type_: package_interface.Named(
                        "Token",
                        "pkg",
                        "pkg/auth",
                        [],
                      ),
                    ),
                  ],
                  return: package_interface.Named("Bool", "", "gleam", []),
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import type { Token } from \"./pkg/auth.js\";
import { validate } from \"./pkg/auth.js\";

const tok: Token = {} as Token;
const _valid: boolean = validate(tok);
",
  )
}

// ---------------------------------------------------------------------------
// Test: Generic ADTs work with type parameters
// ---------------------------------------------------------------------------

pub fn e2e_generic_adt_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg/maybe",
          Module(
            ..empty_module(),
            types: dict.from_list([
              #(
                "Container",
                TypeDefinition(
                  documentation: None,
                  deprecation: None,
                  parameters: 1,
                  constructors: [
                    TypeConstructor(
                      documentation: None,
                      name: "Empty",
                      parameters: [],
                    ),
                    TypeConstructor(
                      documentation: None,
                      name: "Holding",
                      parameters: [
                        Parameter(
                          label: Some("value"),
                          type_: package_interface.Variable(0),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import type { Container, Empty, Holding } from \"./pkg/maybe.js\";

const e: Container<string> = {} as Empty<string>;
const h: Container<number> = {} as Holding<number>;
const _v: number = h.value;
",
  )
}

// ---------------------------------------------------------------------------
// Test: Cross-module type imports are generated
// ---------------------------------------------------------------------------

pub fn e2e_cross_module_imports_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg/types",
          Module(
            ..empty_module(),
            types: dict.from_list([
              #(
                "Color",
                TypeDefinition(
                  documentation: None,
                  deprecation: None,
                  parameters: 0,
                  constructors: [
                    TypeConstructor(
                      documentation: None,
                      name: "Red",
                      parameters: [],
                    ),
                    TypeConstructor(
                      documentation: None,
                      name: "Green",
                      parameters: [],
                    ),
                  ],
                ),
              ),
              #(
                "Point",
                TypeDefinition(
                  documentation: None,
                  deprecation: None,
                  parameters: 0,
                  constructors: [
                    TypeConstructor(
                      documentation: None,
                      name: "Point",
                      parameters: [
                        Parameter(
                          label: Some("x"),
                          type_: package_interface.Named(
                            "Float",
                            "",
                            "gleam",
                            [],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
        #(
          "pkg",
          Module(
            ..empty_module(),
            functions: dict.from_list([
              #(
                "get_color",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [],
                  return: package_interface.Named(
                    "Color",
                    "pkg",
                    "pkg/types",
                    [],
                  ),
                ),
              ),
              #(
                "get_point",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [],
                  return: package_interface.Named(
                    "Point",
                    "pkg",
                    "pkg/types",
                    [],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import type { Color } from \"./pkg/types.js\";
import type { Point } from \"./pkg/types.js\";
import { get_color, get_point } from \"./pkg.js\";

const c: Color = get_color();
const p: Point = get_point();
const _x: number = p.x;
",
  )
}

// ---------------------------------------------------------------------------
// Test: Reserved words are escaped with $
// ---------------------------------------------------------------------------

pub fn e2e_reserved_words_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg",
          Module(
            ..empty_module(),
            functions: dict.from_list([
              #(
                "new",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
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
                  implementations: js_impl(),
                  parameters: [],
                  return: package_interface.Named("Nil", "", "gleam", []),
                ),
              ),
              #(
                "delete",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [],
                  return: package_interface.Named("Bool", "", "gleam", []),
                ),
              ),
              #(
                "safe_name",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [],
                  return: package_interface.Named("String", "", "gleam", []),
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import { new$, null$, delete$, safe_name } from \"./pkg.js\";

const _a: string = new$(\"hello\");
const _b: undefined = null$();
const _c: boolean = delete$();
const _d: string = safe_name();
",
  )
}

// ---------------------------------------------------------------------------
// Test: Option → nullable, Result → discriminated union
// ---------------------------------------------------------------------------

pub fn e2e_option_result_mapping_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg",
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
                    Parameter(
                      label: Some("key"),
                      type_: package_interface.Named("String", "", "gleam", []),
                    ),
                  ],
                  return: package_interface.Named(
                    "Option",
                    "gleam_stdlib",
                    "gleam/option",
                    [package_interface.Named("Int", "", "gleam", [])],
                  ),
                ),
              ),
              #(
                "parse",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [
                    Parameter(
                      label: Some("input"),
                      type_: package_interface.Named("String", "", "gleam", []),
                    ),
                  ],
                  return: package_interface.Named("Result", "", "gleam", [
                    package_interface.Named("Int", "", "gleam", []),
                    package_interface.Named("String", "", "gleam", []),
                  ]),
                ),
              ),
              #(
                "accept_optional",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [
                    Parameter(
                      label: Some("val"),
                      type_: package_interface.Named(
                        "Option",
                        "gleam_stdlib",
                        "gleam/option",
                        [package_interface.Named("String", "", "gleam", [])],
                      ),
                    ),
                  ],
                  return: package_interface.Named("Nil", "", "gleam", []),
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import { find, parse, accept_optional } from \"./pkg.js\";

// Option return
const found = find(\"key\");
if (found !== undefined) {
  const n: number = found;
}

// Option parameter accepts undefined
accept_optional(\"hello\");
accept_optional(undefined);

// Result return
const result = parse(\"42\");
if (result.ok) {
  const val: number = result.value;
} else {
  const err: string = result.error;
}
",
  )
}

// ---------------------------------------------------------------------------
// Test: List → Array, Dict → Map
// ---------------------------------------------------------------------------

pub fn e2e_collection_type_mapping_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg",
          Module(
            ..empty_module(),
            functions: dict.from_list([
              #(
                "sum",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
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
              #(
                "lookup",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [
                    Parameter(
                      label: Some("map"),
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
                  ],
                  return: package_interface.Named("Int", "", "gleam", []),
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import { sum, lookup } from \"./pkg.js\";

const _s: number = sum([1, 2, 3]);
const m = new Map<string, number>();
const _v: number = lookup(m);
",
  )
}

// ---------------------------------------------------------------------------
// Test: Generics, tuples, function parameters
// ---------------------------------------------------------------------------

pub fn e2e_generics_tuples_callbacks_test() {
  let package =
    Package(
      name: "pkg",
      version: "1.0.0",
      gleam_version_constraint: None,
      modules: dict.from_list([
        #(
          "pkg",
          Module(
            ..empty_module(),
            functions: dict.from_list([
              #(
                "identity",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [
                    Parameter(
                      label: Some("value"),
                      type_: package_interface.Variable(1),
                    ),
                  ],
                  return: package_interface.Variable(1),
                ),
              ),
              #(
                "swap",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
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
              #(
                "apply",
                Function(
                  documentation: None,
                  deprecation: None,
                  implementations: js_impl(),
                  parameters: [
                    Parameter(
                      label: Some("value"),
                      type_: package_interface.Variable(1),
                    ),
                    Parameter(
                      label: Some("func"),
                      type_: package_interface.Fn(
                        [package_interface.Variable(1)],
                        package_interface.Variable(2),
                      ),
                    ),
                  ],
                  return: package_interface.Variable(2),
                ),
              ),
            ]),
          ),
        ),
      ]),
    )

  assert_tsc_validates(
    package,
    "import { identity, swap, apply } from \"./pkg.js\";

const _s: string = identity(\"hello\");
const _n: number = identity(42);

const _swapped: readonly [string, number] = swap(
  [42, \"hello\"] as const as readonly [number, string]
);

const _result: number = apply(\"hello\", (s: string) => s.length);
",
  )
}

// ---------------------------------------------------------------------------
// Test: JSDoc is forwarded from documentation
// ---------------------------------------------------------------------------

pub fn e2e_jsdoc_forwarding_test() {
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "greet",
          Function(
            documentation: Some(" Say hello to someone.\n"),
            deprecation: None,
            implementations: js_impl(),
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

  let result = dts.emit_module(module, "pkg", "pkg")
  result.content |> string.contains("/**") |> expect.to_be_true()
  result.content
  |> string.contains("Say hello to someone.")
  |> expect.to_be_true()
}

// ---------------------------------------------------------------------------
// Test: Full multi-module package (comprehensive integration)
// ---------------------------------------------------------------------------

pub fn e2e_full_package_test() {
  let package =
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

  assert_tsc_validates(
    package,
    "import type { Color, Point, Token, Container, Empty, Holding } from \"./testlib/types.js\";
import { to_string } from \"./testlib/types.js\";
import { new$, null$, maybe_parse, safe_divide, identity, swap, map_point, sum, lookup } from \"./testlib/utils.js\";
import { default_color, origin, wrap } from \"./testlib.js\";

const color: Color = default_color();
const pt: Point = { x: 1.0, y: 2.0 };
const _x: number = pt.x;
const _tok: Token = {} as Token;
const _e: Container<string> = {} as Empty<string>;
const _h: Container<number> = {} as Holding<number>;
const _o: Point = origin();
const _w: Container<string> = wrap(\"hello\");
const _t1: Token = new$(\"abc\");
const _t2: Token = null$();
const _mp: number = maybe_parse(\"hello\");
const _mp2: number = maybe_parse(undefined);
const result = safe_divide(10.0, 3.0);
if (result.ok) { const _v: number = result.value; }
else { const _e: string = result.error; }
const _id: string = identity(\"hello\");
const _sw: readonly [string, number] = swap([42, \"hello\"] as const as readonly [number, string]);
const _mp3: Point = map_point(pt, (n: number) => n * 2);
const _s: number = sum([1, 2, 3]);
const m = new Map<string, number>();
const _lr = lookup(m, \"key\");
if (_lr.ok) { const _v: number = _lr.value; }
else { const _e: undefined = _lr.error; }
const _cs: string = to_string(color);
",
  )
}

// ---------------------------------------------------------------------------
// Test: Expected warnings count
// ---------------------------------------------------------------------------

pub fn e2e_expected_warnings_test() {
  let package =
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

  let all_warnings =
    dict.to_list(package.modules)
    |> list.flat_map(fn(pair) {
      let #(module_name, module) = pair
      let result = dts.emit_module(module, package.name, module_name)
      result.warnings
    })

  all_warnings
  |> list.filter(fn(w) { string.contains(w, "Opaque type") })
  |> list.length
  |> expect.to_equal(1)
}

// ---------------------------------------------------------------------------
// Shared module builders for the full-package and warnings tests
// ---------------------------------------------------------------------------

fn types_module() -> Module {
  Module(
    ..empty_module(),
    types: dict.from_list([
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
      #(
        "Point",
        TypeDefinition(
          documentation: None,
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
      #(
        "Token",
        TypeDefinition(
          documentation: None,
          deprecation: None,
          parameters: 0,
          constructors: [],
        ),
      ),
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
          implementations: js_impl(),
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
    ..empty_module(),
    functions: dict.from_list([
      #(
        "new",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "maybe_parse",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "safe_divide",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "identity",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
          parameters: [
            Parameter(
              label: Some("value"),
              type_: package_interface.Variable(1),
            ),
          ],
          return: package_interface.Variable(1),
        ),
      ),
      #(
        "swap",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "map_point",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "sum",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "lookup",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
      #(
        "null",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
    ..empty_module(),
    functions: dict.from_list([
      #(
        "default_color",
        Function(
          documentation: Some(" Get the default color.\n"),
          deprecation: None,
          implementations: js_impl(),
          parameters: [],
          return: package_interface.Named(
            "Color",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
      #(
        "origin",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
          parameters: [],
          return: package_interface.Named(
            "Point",
            "testlib",
            "testlib/types",
            [],
          ),
        ),
      ),
      #(
        "wrap",
        Function(
          documentation: None,
          deprecation: None,
          implementations: js_impl(),
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
