# External Type Declarations Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable talc to resolve external Gleam package types in wrapper `.d.ts` files using local `.d.ts` type declaration files, falling back to `unknown` for unresolved types.

**Architecture:** Add a type declarations directory (`talc-types/` by default) where users place `.d.ts` files mirroring Gleam's `{package}/{module}` structure. During wrapper generation, talc checks file existence to determine type availability, generates proper `import type` statements for resolved types, and emits `unknown` for unresolved ones. Type declaration files are copied to `dist/_types/` in the npm output with empty `.mjs` stubs for TypeScript module resolution.

**Tech Stack:** Gleam (BEAM target), startest (testing), simplifile (filesystem), gleam_package_interface (type introspection)

**Spec:** `docs/superpowers/specs/2026-03-26-external-type-declarations-design.md`

---

### Task 1: Remove dead `type_maps` from config

**Files:**
- Modify: `src/talc/talc_config.gleam` — remove `type_maps` field, `parse_type_maps` function
- Modify: `test/talc_config_test.gleam` — remove/update `type_maps` tests

- [ ] **Step 1: Update `TalcConfig` type and `default()` — remove `type_maps`**

In `src/talc/talc_config.gleam`:
- Remove `type_maps: Dict(String, String)` from the `TalcConfig` type (line 35)
- Remove `type_maps: dict.new()` from `default()` (line 48)
- Remove `import gleam/dict.{type Dict}` if no longer used
- Remove `parse_type_maps` function (lines 181-194)
- Remove `type_maps` from `parse()` function (lines 89, 96)

- [ ] **Step 2: Update tests — remove `type_maps` tests**

In `test/talc_config_test.gleam`:
- Remove `parse_type_maps_test` (lines 175-190)
- Remove `parse_empty_type_maps_test` (lines 192-195)
- Remove `default_type_maps_test` (lines 197-200)
- Remove `import gleam/dict` if no longer used

- [ ] **Step 3: Run tests to verify nothing breaks**

Run: `gleam test`
Expected: All tests pass (minus the 3 removed tests)

- [ ] **Step 4: Commit**

```bash
git add src/talc/talc_config.gleam test/talc_config_test.gleam
git commit -m "refactor(config): remove dead type_maps field

Superseded by the type declarations directory system.
Addresses #2."
```

---

### Task 2: Add `type_declarations_dir` to config

**Files:**
- Modify: `src/talc/talc_config.gleam` — add field and parsing
- Modify: `test/talc_config_test.gleam` — add tests

- [ ] **Step 1: Write the failing tests**

Add to `test/talc_config_test.gleam`:

```gleam
pub fn default_type_declarations_dir_test() {
  let config = talc_config.default()
  config.type_declarations_dir |> expect.to_equal("talc-types")
}

pub fn parse_type_declarations_dir_test() {
  let ccl =
    "type_declarations_dir = custom-types
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  config.type_declarations_dir |> expect.to_equal("custom-types")
}

pub fn parse_empty_type_declarations_dir_test() {
  let config = talc_config.parse("") |> expect.to_be_ok()
  config.type_declarations_dir |> expect.to_equal("talc-types")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `gleam test`
Expected: Compilation error — `type_declarations_dir` field does not exist on `TalcConfig`

- [ ] **Step 3: Add `type_declarations_dir` field and parsing**

In `src/talc/talc_config.gleam`:

Add to `TalcConfig`:
```gleam
/// Directory containing .d.ts type declaration files for external types.
/// Mirrors Gleam's {package}/{module} structure.
type_declarations_dir: String,
```

Add to `default()`:
```gleam
type_declarations_dir: "talc-types",
```

Add parsing function:
```gleam
fn parse_type_declarations_dir(ccl: CCL) -> String {
  case access.get_string(ccl, ["type_declarations_dir"]) {
    Ok(s) -> s
    Error(_) -> "talc-types"
  }
}
```

Wire into `parse()`:
```gleam
let type_declarations_dir = parse_type_declarations_dir(ccl)
// ... in the TalcConfig constructor:
type_declarations_dir: type_declarations_dir,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add src/talc/talc_config.gleam test/talc_config_test.gleam
git commit -m "feat(config): add type_declarations_dir setting

Defaults to 'talc-types'. Configurable in talc.ccl.
Part of #2."
```

---

### Task 3: Change `type_to_ts` fallback from bare name to `unknown`

**Files:**
- Modify: `src/talc/wrapper.gleam:439-446` — change fallback case
- Modify: `test/wrapper_test.gleam` — add test for external type

- [ ] **Step 1: Write the failing test**

Add to `test/wrapper_test.gleam`:

```gleam
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
  // External type without declaration should be unknown
  result.dts |> string_contains("Result<unknown, undefined>") |> expect.to_be_true()
}
```

Note: This test uses the NEW signature of `generate_module_wrapper` with a third `available_type_files` parameter (a `Set(#(String, String))` of `#(package, module)` pairs). Add `import gleam/set` to the test imports.

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: Compilation error — `generate_module_wrapper` takes 2 arguments, not 3

- [ ] **Step 3: Update `generate_module_wrapper` signature and `type_to_ts` fallback**

In `src/talc/wrapper.gleam`:

Update the function signature (add `import gleam/set.{type Set}` at top):
```gleam
pub fn generate_module_wrapper(
  module: Module,
  module_name: String,
  available_type_files: Set(#(String, String)),
) -> WrapperResult {
```

Thread `available_type_files` through to `generate_dts` and `type_to_ts`.

Change the `type_to_ts` signature to accept `available_type_files`:
```gleam
fn type_to_ts(
  t: Type,
  vars: Dict(Int, String),
  available_type_files: Set(#(String, String)),
) -> String {
```

Change the fallback case (currently lines 439-446) to:
```gleam
    // Non-prelude named types: check for type declaration file
    Named(name: n, package: p, module: m, parameters: params) ->
      case set.contains(available_type_files, #(p, m)) {
        True ->
          case params {
            [] -> n
            ps -> {
              let type_args =
                list.map(ps, fn(param) {
                  type_to_ts(param, vars, available_type_files)
                })
              n <> "<" <> string.join(type_args, ", ") <> ">"
            }
          }
        False -> "unknown"
      }
```

Update all recursive `type_to_ts` calls within the function to pass `available_type_files` through.

Also update `generate_mjs` — it doesn't call `type_to_ts` so no changes needed there.

Update `generate_dts` to accept and pass `available_type_files`:
```gleam
fn generate_dts(
  functions: List(#(String, Function, Bool)),
  module_name: String,
  available_type_files: Set(#(String, String)),
) -> String {
```

Update `generate_wrapper_fn_dts` similarly:
```gleam
fn generate_wrapper_fn_dts(
  name: String,
  func: Function,
  available_type_files: Set(#(String, String)),
) -> String {
```

- [ ] **Step 4: Update existing tests to pass `set.new()` as third argument**

In `test/wrapper_test.gleam`, update ALL existing calls to `wrapper.generate_module_wrapper`:
```gleam
// Before:
let result = wrapper.generate_module_wrapper(module, "my_lib")
// After:
let result = wrapper.generate_module_wrapper(module, "my_lib", set.new())
```

There are 7 existing test functions that call `generate_module_wrapper` — update all of them.

- [ ] **Step 5: Update `talc.gleam` to pass `set.new()` (placeholder)**

In `src/talc.gleam`, update line 203:
```gleam
// Before:
let result = wrapper.generate_module_wrapper(module, module_name)
// After:
let result = wrapper.generate_module_wrapper(module, module_name, set.new())
```

Add `import gleam/set` to the imports.

- [ ] **Step 6: Run tests to verify they pass**

Run: `gleam test`
Expected: All tests pass, including the new `external_type_emits_unknown_test`

- [ ] **Step 7: Commit**

```bash
git add src/talc/wrapper.gleam src/talc.gleam test/wrapper_test.gleam
git commit -m "feat(wrapper): emit unknown for unresolved external types

Changes the type_to_ts fallback from bare type names to 'unknown'
for non-prelude named types without a matching type declaration file.
This produces valid TypeScript instead of broken references.

Part of #2."
```

---

### Task 4: Generate `import type` statements for resolved external types

**Files:**
- Modify: `src/talc/wrapper.gleam` — collect external types, generate imports
- Modify: `test/wrapper_test.gleam` — test with available declarations

- [ ] **Step 1: Write the failing test**

Add to `test/wrapper_test.gleam`:

```gleam
pub fn resolved_external_type_import_test() {
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

  let available = set.from_list([#("gleam_json", "gleam/json")])
  let result =
    wrapper.generate_module_wrapper(module, "my_lib", available)
  result.has_wrapped_functions |> expect.to_be_true()
  // Should import from _types directory
  result.dts
  |> string_contains(
    "import type { Json } from \"../_types/gleam_json/gleam/json.mjs\"",
  )
  |> expect.to_be_true()
  // Should use the type name, not unknown
  result.dts |> string_contains("Result<Json, undefined>") |> expect.to_be_true()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `result.dts` contains `Result<Json, undefined>` (since declaration file is available) but no import statement is generated

- [ ] **Step 3: Add `collect_non_prelude_named_types` function**

Add to `src/talc/wrapper.gleam`:

```gleam
/// Collects all non-prelude Named types from a type tree.
/// Returns a list of #(package, module, name) tuples.
fn collect_non_prelude_named_types(t: Type) -> List(#(String, String, String)) {
  case t {
    Named(name: "Int", package: "", module: "gleam", ..)
    | Named(name: "Float", package: "", module: "gleam", ..)
    | Named(name: "String", package: "", module: "gleam", ..)
    | Named(name: "Bool", package: "", module: "gleam", ..)
    | Named(name: "Nil", package: "", module: "gleam", ..)
    | Named(name: "BitArray", package: "", module: "gleam", ..)
    | Named(name: "UtfCodepoint", package: "", module: "gleam", ..)
    | Named(name: "List", package: "", module: "gleam", ..)
    | Named(name: "Result", package: "", module: "gleam", ..)
    | Named(
        name: "Option",
        package: "gleam_stdlib",
        module: "gleam/option",
        ..,
      ) -> list.flat_map(get_type_parameters(t), collect_non_prelude_named_types)
    Named(name: n, package: p, module: m, parameters: params) -> {
      let self = [#(p, m, n)]
      let nested = list.flat_map(params, collect_non_prelude_named_types)
      list.append(self, nested)
    }
    Tuple(elements: elems) ->
      list.flat_map(elems, collect_non_prelude_named_types)
    Fn(parameters: params, return: ret) ->
      list.append(
        list.flat_map(params, collect_non_prelude_named_types),
        collect_non_prelude_named_types(ret),
      )
    Variable(..) -> []
  }
}

/// Extracts type parameters from a Named type.
fn get_type_parameters(t: Type) -> List(Type) {
  case t {
    Named(parameters: params, ..) -> params
    _ -> []
  }
}
```

- [ ] **Step 4: Update `generate_dts` to emit external type imports**

In `generate_dts`, after collecting prelude types and before the import block, add collection and import generation for external types:

```gleam
  // Collect external types from wrapped functions that have declaration files
  let external_types =
    list.flat_map(wrapped, fn(t) {
      let func = t.1
      list.append(
        list.flat_map(func.parameters, fn(p) {
          collect_non_prelude_named_types(p.type_)
        }),
        collect_non_prelude_named_types(func.return),
      )
    })
    |> list.filter(fn(triple) {
      let #(p, m, _n) = triple
      set.contains(available_type_files, #(p, m))
    })
    |> list.unique()

  // Group by (package, module) for import statements
  let external_imports =
    external_types
    |> list.group(fn(triple) {
      let #(p, m, _n) = triple
      #(p, m)
    })
    |> dict.to_list()
    |> list.sort(fn(a, b) {
      string.compare(
        { a.0 }.0 <> "/" <> { a.0 }.1,
        { b.0 }.0 <> "/" <> { b.0 }.1,
      )
    })
    |> list.map(fn(pair) {
      let #(#(p, m), types) = pair
      let names =
        list.map(types, fn(t) { t.2 })
        |> list.unique()
        |> list.sort(string.compare)
      "import type { "
      <> string.join(names, ", ")
      <> " } from \"../_types/"
      <> p
      <> "/"
      <> m
      <> ".mjs\";"
    })

  // Add external imports to mut_imports
  let mut_imports = list.append(list.reverse(external_imports), mut_imports)
```

Insert this block after the `all_wrapped_types` / prelude imports section and before the existing `mut_imports` for Result/Option.

- [ ] **Step 5: Run tests to verify they pass**

Run: `gleam test`
Expected: All tests pass, including `resolved_external_type_import_test`

- [ ] **Step 6: Commit**

```bash
git add src/talc/wrapper.gleam test/wrapper_test.gleam
git commit -m "feat(wrapper): generate imports for resolved external types

When a type declaration file exists for a package/module, the wrapper
.d.ts now generates proper 'import type' statements from the
_types directory.

Part of #2."
```

---

### Task 5: Add warnings for unresolved external types

**Files:**
- Modify: `src/talc/wrapper.gleam` — add `warnings` to `WrapperResult`
- Modify: `src/talc.gleam` — collect and surface warnings
- Modify: `test/wrapper_test.gleam` — test warnings

- [ ] **Step 1: Write the failing test**

Add to `test/wrapper_test.gleam`:

```gleam
pub fn unresolved_external_type_warning_test() {
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
  result.warnings
  |> list.any(fn(w) {
    string.contains(w, "Json")
    && string.contains(w, "gleam_json")
  })
  |> expect.to_be_true()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: Compilation error — `warnings` field does not exist on `WrapperResult`

- [ ] **Step 3: Add `warnings` field to `WrapperResult`**

In `src/talc/wrapper.gleam`, update `WrapperResult`:
```gleam
pub type WrapperResult {
  WrapperResult(
    mjs: String,
    dts: String,
    has_wrapped_functions: Bool,
    /// Warnings for unresolved external types (emitted as unknown).
    warnings: List(String),
    /// Set of #(package, module) pairs for type files actually used.
    resolved_type_files: Set(#(String, String)),
  )
}
```

In `generate_module_wrapper`, collect unresolved types, resolved files, and generate warnings:

```gleam
  // Collect all external types from wrapped functions
  let all_external_types =
    list.flat_map(analyzed, fn(t) {
      case t.2 {
        True -> {
          let func = t.1
          list.append(
            list.flat_map(func.parameters, fn(p) {
              collect_non_prelude_named_types(p.type_)
            }),
            collect_non_prelude_named_types(func.return),
          )
        }
        False -> []
      }
    })
    |> list.unique()

  // Track which type files were actually resolved (for output copying)
  let resolved_type_files =
    all_external_types
    |> list.filter(fn(triple) {
      let #(p, m, _n) = triple
      set.contains(available_type_files, #(p, m))
    })
    |> list.map(fn(triple) {
      let #(p, m, _n) = triple
      #(p, m)
    })
    |> list.unique()
    |> set.from_list()

  let warnings =
    all_external_types
    |> list.filter(fn(triple) {
      let #(p, m, _n) = triple
      !set.contains(available_type_files, #(p, m))
    })
    |> list.map(fn(triple) {
      let #(p, m, n) = triple
      "Type "
      <> n
      <> " from "
      <> p
      <> "/"
      <> m
      <> " has no type declaration — emitting as unknown"
    })

  WrapperResult(
    mjs: mjs,
    dts: dts,
    has_wrapped_functions: has_wrapped,
    warnings: warnings,
    resolved_type_files: resolved_type_files,
  )
```

- [ ] **Step 4: Update `talc.gleam` to collect wrapper warnings**

In `src/talc.gleam`, in the `run_generate` function's True branch (around line 200), collect warnings from each wrapper result:

```gleam
        case result.has_wrapped_functions {
          True -> {
            let wrapper_mjs_path = "_wrapper/" <> module_name <> ".mjs"
            let wrapper_dts_path = "_wrapper/" <> module_name <> ".d.ts"
            #(
              list.append(files, [
                #(wrapper_mjs_path, result.mjs),
                #(wrapper_dts_path, result.dts),
              ]),
              set.insert(wrapped, module_name),
              list.append(warnings, result.warnings),
            )
          }
          False -> #(files, wrapped, list.append(warnings, result.warnings))
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add src/talc/wrapper.gleam src/talc.gleam test/wrapper_test.gleam
git commit -m "feat(wrapper): add warnings for unresolved external types

WrapperResult now includes a warnings list. Types without matching
declaration files produce a descriptive warning.

Part of #2."
```

---

### Task 6: Scan type declarations directory and wire into wrapper generation

**Files:**
- Modify: `src/talc.gleam` — scan directory, pass to wrapper
- Modify: `test/wrapper_test.gleam` — add parameterized type test

- [ ] **Step 1: Write test for parameterized external type**

Add to `test/wrapper_test.gleam`:

```gleam
pub fn parameterized_external_type_test() {
  let subject_type =
    Named(
      name: "Subject",
      package: "gleam_erlang",
      module: "gleam/erlang/process",
      parameters: [Variable(id: 1)],
    )
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "subscribe",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("topic"), type_: string_type()),
            ],
            return: result_type(subject_type, nil_type()),
          ),
        ),
      ]),
    )

  let available =
    set.from_list([#("gleam_erlang", "gleam/erlang/process")])
  let result =
    wrapper.generate_module_wrapper(module, "my_lib", available)
  result.has_wrapped_functions |> expect.to_be_true()
  result.dts
  |> string_contains("Result<Subject<A>, undefined>")
  |> expect.to_be_true()
  result.dts
  |> string_contains(
    "import type { Subject } from \"../_types/gleam_erlang/gleam/erlang/process.mjs\"",
  )
  |> expect.to_be_true()
}
```

- [ ] **Step 2: Run test to verify it passes (should pass with existing implementation)**

Run: `gleam test`
Expected: PASS — parameterized types already handled by type_to_ts

- [ ] **Step 3: Add directory scanning function to `talc.gleam`**

In `src/talc.gleam`, add a function to scan the type declarations directory:

```gleam
/// Scans the type declarations directory and returns a set of
/// available #(package, module) pairs based on .d.ts file existence.
fn scan_type_declarations(dir: String) -> set.Set(#(String, String)) {
  case simplifile.is_directory(dir) {
    Ok(True) -> scan_type_dir_recursive(dir, dir)
    _ -> set.new()
  }
}

fn scan_type_dir_recursive(
  base_dir: String,
  current_dir: String,
) -> set.Set(#(String, String)) {
  case simplifile.read_directory(current_dir) {
    Ok(entries) ->
      list.fold(entries, set.new(), fn(acc, entry) {
        let path = current_dir <> "/" <> entry
        case simplifile.is_directory(path) {
          Ok(True) ->
            set.union(acc, scan_type_dir_recursive(base_dir, path))
          _ ->
            case string.ends_with(entry, ".d.ts") {
              True -> {
                // Extract relative path: remove base_dir prefix and .d.ts suffix
                let rel =
                  string.drop_start(path, string.length(base_dir) + 1)
                let module_path =
                  string.drop_end(rel, string.length(".d.ts"))
                // Split into package (first segment) and module (rest)
                case string.split(module_path, "/") {
                  [package, ..module_parts] ->
                    set.insert(acc, #(
                      package,
                      string.join(module_parts, "/"),
                    ))
                  _ -> acc
                }
              }
              False -> acc
            }
        }
      })
    Error(_) -> set.new()
  }
}
```

Add `import simplifile` and `import gleam/string` to `talc.gleam` imports if not already present.

- [ ] **Step 4: Wire scanning into `run_generate`**

In `run_generate`, after loading `effective_talc` and before the wrapper generation block:

```gleam
  // Scan type declarations directory for available .d.ts files
  let available_type_files =
    scan_type_declarations(effective_talc.type_declarations_dir)
```

Then update the wrapper call:
```gleam
        let result =
          wrapper.generate_module_wrapper(
            module,
            module_name,
            available_type_files,
          )
```

- [ ] **Step 5: Run tests to verify everything passes**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add src/talc.gleam test/wrapper_test.gleam
git commit -m "feat: scan type declarations directory for available types

Reads talc-types/ (or configured dir) at build time and passes
available type file locations to wrapper generation.

Part of #2."
```

---

### Task 7: Copy type declaration files to npm output

**Files:**
- Modify: `src/talc/output.gleam` — add copy function for type declarations
- Modify: `src/talc.gleam` — wire type file copying into output

- [ ] **Step 1: Add `copy_type_declarations` function to `output.gleam`**

In `src/talc/output.gleam`, add:

```gleam
/// Copies referenced type declaration .d.ts files to dist/_types/
/// and generates empty .mjs stubs for TypeScript module resolution.
/// `referenced_files` is a set of #(package, module) pairs.
pub fn copy_type_declarations(
  source_dir: String,
  output_dir: String,
  referenced_files: set.Set(#(String, String)),
) -> Result(List(String), OutputError) {
  let types_dir = output_dir <> "/dist/_types"
  let pairs = set.to_list(referenced_files)

  list.try_fold(pairs, [], fn(acc, pair) {
    let #(package, module) = pair
    let src = source_dir <> "/" <> package <> "/" <> module <> ".d.ts"
    let dest_dts = types_dir <> "/" <> package <> "/" <> module <> ".d.ts"
    let dest_mjs = types_dir <> "/" <> package <> "/" <> module <> ".mjs"
    let dest_dir = string_before_last(dest_dts, "/")

    case simplifile.is_file(src) {
      Ok(True) -> {
        use _ <- try_result(
          simplifile.create_directory_all(dest_dir)
          |> map_file_error(DirectoryError(dest_dir, _)),
        )
        use _ <- try_result(
          simplifile.copy_file(at: src, to: dest_dts)
          |> map_file_error(CopyError(src, dest_dts, _)),
        )
        use _ <- try_result(
          simplifile.write(to: dest_mjs, contents: "")
          |> map_file_error(WriteError(dest_mjs, _)),
        )
        Ok(list.append(acc, [dest_dts, dest_mjs]))
      }
      _ -> Ok(acc)
    }
  })
}
```

Add `import gleam/set` to the imports.

- [ ] **Step 2: Wire into `talc.gleam` output step**

In `run_generate`, after the wrapper generation `list.fold`, collect resolved type files from all wrapper results. In the fold accumulator, add a fourth element to track resolved files. Then pass only the referenced set to `copy_type_declarations`. Add after the wrapper generation block and before the `output.write` call:

Update the fold accumulator from `#(files, wrapped, warnings)` to `#(files, wrapped, warnings, resolved_types)` where `resolved_types` is a `set.Set(#(String, String))`:

```gleam
      |> list.fold(#([], set.new(), [], set.new()), fn(acc, pair) {
        let #(files, wrapped, warnings, resolved_types) = acc
        let #(module_name, module) = pair
        let result =
          wrapper.generate_module_wrapper(
            module,
            module_name,
            available_type_files,
          )
        let new_resolved = set.union(resolved_types, result.resolved_type_files)
        case result.has_wrapped_functions {
          True -> {
            let wrapper_mjs_path = "_wrapper/" <> module_name <> ".mjs"
            let wrapper_dts_path = "_wrapper/" <> module_name <> ".d.ts"
            #(
              list.append(files, [
                #(wrapper_mjs_path, result.mjs),
                #(wrapper_dts_path, result.dts),
              ]),
              set.insert(wrapped, module_name),
              list.append(warnings, result.warnings),
              new_resolved,
            )
          }
          False -> #(files, wrapped, list.append(warnings, result.warnings), new_resolved)
        }
      })
```

Then after the fold:

```gleam
  // Copy only referenced type declaration files to output
  use type_files <- try_ok(
    output.copy_type_declarations(
      effective_talc.type_declarations_dir,
      effective_output_dir,
      all_resolved_types,
    )
    |> map_error(output.error_to_string),
  )
```

Include `type_files` in the final written files list.

- [ ] **Step 3: Run tests to verify nothing breaks**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add src/talc/output.gleam src/talc.gleam
git commit -m "feat(output): copy type declaration files to npm output

Copies .d.ts files from the type declarations directory to
dist/_types/ and generates empty .mjs stubs for TypeScript
module resolution.

Part of #2."
```

---

### Task 8: Add mixed/edge-case tests

**Files:**
- Modify: `test/wrapper_test.gleam` — comprehensive edge case tests

- [ ] **Step 1: Write edge case tests**

Add to `test/wrapper_test.gleam`:

```gleam
pub fn mixed_prelude_and_external_types_test() {
  let json_type =
    Named(
      name: "Json",
      package: "gleam_json",
      module: "gleam/json",
      parameters: [],
    )
  let list_of_json =
    Named(name: "List", package: "", module: "gleam", parameters: [json_type])
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "parse_all",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("input"), type_: string_type()),
            ],
            return: result_type(list_of_json, string_type()),
          ),
        ),
      ]),
    )

  let available = set.from_list([#("gleam_json", "gleam/json")])
  let result =
    wrapper.generate_module_wrapper(module, "my_lib", available)
  result.has_wrapped_functions |> expect.to_be_true()
  // Should have both List and Json imports
  result.dts
  |> string_contains("import type { List } from \"../gleam.d.mts\"")
  |> expect.to_be_true()
  result.dts
  |> string_contains(
    "import type { Json } from \"../_types/gleam_json/gleam/json.mjs\"",
  )
  |> expect.to_be_true()
  result.dts
  |> string_contains("Result<List<Json>, string>")
  |> expect.to_be_true()
}

pub fn multiple_external_types_same_module_test() {
  let json_type =
    Named(
      name: "Json",
      package: "gleam_json",
      module: "gleam/json",
      parameters: [],
    )
  let decode_error_type =
    Named(
      name: "DecodeError",
      package: "gleam_json",
      module: "gleam/json",
      parameters: [],
    )
  let module =
    Module(
      ..empty_module(),
      functions: dict.from_list([
        #(
          "decode",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("input"), type_: json_type),
            ],
            return: result_type(string_type(), decode_error_type),
          ),
        ),
      ]),
    )

  let available = set.from_list([#("gleam_json", "gleam/json")])
  let result =
    wrapper.generate_module_wrapper(module, "my_lib", available)
  result.has_wrapped_functions |> expect.to_be_true()
  // Should import both types from same module in one statement
  result.dts
  |> string_contains("import type { DecodeError, Json }")
  |> expect.to_be_true()
  result.dts
  |> string_contains("Result<string, DecodeError>")
  |> expect.to_be_true()
}

pub fn no_warnings_when_type_resolved_test() {
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

  let available = set.from_list([#("gleam_json", "gleam/json")])
  let result =
    wrapper.generate_module_wrapper(module, "my_lib", available)
  result.warnings |> expect.to_equal([])
}

pub fn passthrough_with_external_type_no_warning_test() {
  // External types in passthrough functions (not wrapped) should not warn
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
          "make_json",
          Function(
            documentation: None,
            deprecation: None,
            implementations: js_impl(),
            parameters: [
              Parameter(label: Some("value"), type_: string_type()),
            ],
            return: json_type,
          ),
        ),
      ]),
    )

  let result =
    wrapper.generate_module_wrapper(module, "my_lib", set.new())
  // Not wrapped (no Result/Option), so no warnings
  result.has_wrapped_functions |> expect.to_be_false()
  result.warnings |> expect.to_equal([])
}
```

- [ ] **Step 2: Run tests**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add test/wrapper_test.gleam
git commit -m "test(wrapper): add edge case tests for external type resolution

Tests mixed prelude+external types, multiple types from same module,
warning behavior, and passthrough functions with external types.

Part of #2."
```

---

### Task 9: Final integration verification

- [ ] **Step 1: Run full test suite**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 2: Run format and check**

Run: `gleam format src test && gleam check`
Expected: Clean

- [ ] **Step 3: Verify build**

Run: `gleam build`
Expected: Clean build

- [ ] **Step 4: Final commit (if formatting changed anything)**

```bash
git add -A
git commit -m "style: format code"
```

- [ ] **Step 5: Comment on issue #2**

```bash
gh issue comment 2 --body "Implemented external type declarations system. Wrapper .d.ts files now resolve external types from local talc-types/ directory, falling back to unknown. See spec at docs/superpowers/specs/2026-03-26-external-type-declarations-design.md. Closes #2."
```
