# External Type Declarations for talc

**Date**: 2026-03-26
**Status**: Approved
**Issue**: #2

## Problem

When talc generates wrapper `.d.ts` files (for true-myth Result/Option conversion), functions that reference types from external Gleam packages produce invalid TypeScript. The `type_to_ts` function in `wrapper.gleam` emits bare type names (e.g., `Json`) with no import statement.

Example: a function `encode(value: String) -> Result(Json, Nil)` produces a wrapper `.d.ts` containing `Result<Json, undefined>` where `Json` is never imported or declared.

**Behavior change**: The current fallback emits bare type names (technically invalid TypeScript). This design changes the fallback to `unknown` (valid TypeScript), which is a deliberate trade-off — correctness over optimistic name emission.

### Why not use `@external` annotations?

Gleam v1.14.0 introduced `@external(javascript, ...)` annotations on types, which the Gleam compiler uses to generate proper imports in `.d.mts` files. However, `gleam_package_interface` v3.0.1 (latest) does **not** expose this annotation data. The `TypeDefinition` type only contains `documentation`, `deprecation`, `parameters`, and `constructors` — no external annotation fields.

Until upstream support is added, talc needs an alternative mechanism.

### Relationship to `type_maps`

`TalcConfig` already has a `type_maps: Dict(String, String)` field that maps Gleam package names to npm package names. This field is parsed from `talc.ccl` but is **dead code** — it is not referenced anywhere in `talc.gleam` or the wrapper/output pipeline. It was part of the old architecture (before the switch to Gleam's native `.d.mts` files).

The new type declarations system **supersedes** `type_maps`. As part of this work, `type_maps` should be removed from `TalcConfig` and its parsing code.

## Solution

A local type declaration system inspired by DefinitelyTyped. Users provide standard `.d.ts` files that map Gleam package types to TypeScript types. Types without declarations fall back to `unknown`.

## Design

### Type Declaration Directory

- **Default location**: `talc-types/` in the project root
- **Configurable** in `talc.ccl`: `type_declarations_dir = ./custom-types`
- **File layout** mirrors Gleam's `{package}/{module}` structure:

```
talc-types/
  gleam_json/
    gleam/
      json.d.ts          -> export type Json = string;
  gleam_erlang/
    gleam/
      erlang/
        process.d.ts     -> export type Subject<T> = { readonly phantom: T };
  birl/
    birl.d.ts            -> export type Time = Date;
```

### File Format

Standard TypeScript `.d.ts` with exported type declarations:

```typescript
// talc-types/gleam_json/gleam/json.d.ts
export type Json = string;
```

```typescript
// talc-types/gleam_erlang/gleam/erlang/process.d.ts
export type Subject<T> = { readonly phantom: T };
```

This format is familiar to TypeScript developers, has editor support (syntax highlighting, validation), and can express any TypeScript type including generics.

### `.d.ts` File Discovery (No Parsing)

talc does **not** parse `.d.ts` files. It uses file existence as the sole resolution signal:

- If `talc-types/{package}/{module}.d.ts` exists → the type is considered available
- talc generates an `import type { TypeName }` from the copied file
- If the `.d.ts` file doesn't actually export that type name, TypeScript's compiler will catch it when the npm consumer compiles — talc trusts the user's type declarations

This avoids the need for a TypeScript parser in Gleam/Erlang. Type correctness is validated downstream by `tsc`, not by talc.

### Import Path Strategy

TypeScript does not allow importing directly from `.d.ts` files. The standard pattern is to import from a `.js` path, and TypeScript resolves the corresponding `.d.ts` automatically. For each type declaration `.d.ts` file copied to `dist/_types/`, talc also generates an empty `.mjs` stub:

```
dist/_types/gleam_json/gleam/json.d.ts    <- actual type declarations
dist/_types/gleam_json/gleam/json.mjs     <- empty file (module resolution target)
```

The wrapper `.d.ts` imports using the `.mjs` extension:

```typescript
import type { Json } from "../_types/gleam_json/gleam/json.mjs";
```

TypeScript resolves this to the `.d.ts` file via standard module resolution.

### Type Resolution Chain

When `type_to_ts` encounters a `Named` type, it uses the following resolution chain. The definition of "non-prelude named type" is: any `Named` where the combination of `package` and `module` is not matched by steps 1–3.

1. **Prelude types** (package `""`, module `"gleam"`) → mapped to TS primitives (`Int` → `number`, etc.) — existing behavior, unchanged
2. **Result** (package `""`, module `"gleam"`) → `Result<T, E>` from true-myth — existing behavior, unchanged
3. **Option** (package `"gleam_stdlib"`, module `"gleam/option"`) → `Maybe<T>` from true-myth — existing behavior, unchanged
4. **Type declaration file exists for `{package}/{module}`** → emit the type name, generate `import type` from the copied `.d.ts`
5. **No type declaration file** → emit `unknown`

Step 4 applies to ALL non-prelude named types regardless of whether they come from the current package or an external package. This means same-package custom types also benefit from the type declarations system — users can provide `.d.ts` files for their own package's types if needed. (Future work may add automatic resolution of same-package types from the native `.d.mts` files.)

### Output Structure

talc copies matched type declaration files into the npm package output under `dist/_types/`, with an empty `.mjs` stub alongside each:

```
npm_dist/
  dist/
    _types/                              <- copied from talc-types/
      gleam_json/
        gleam/
          json.d.ts
          json.mjs                       <- empty stub for module resolution
    _wrapper/
      my_module.d.ts                     <- imports from ../_types/gleam_json/gleam/json.mjs
    my_module.mjs
    my_module.d.mts
    gleam.mjs
    gleam.d.mts
  prelude.mjs
  prelude.d.mts
  package.json
```

This makes the npm package self-contained — it works after `npm pack`/`npm publish`.

### Config Changes

Add `type_declarations_dir` to `talc.ccl` config and remove `type_maps`:

```
package =
  name = my-gleam-lib
  version = 1.0.0
  output_dir = npm_dist

type_declarations_dir = talc-types

use_true_myth = true
```

Default value: `"talc-types"`. The directory is optional — if it doesn't exist, all non-prelude named types resolve to `unknown`.

## Changes Required

### `talc_config.gleam`
- Add `type_declarations_dir: String` field to `TalcConfig` with default `"talc-types"`
- Parse the field from `talc.ccl`
- Remove `type_maps` field and its parsing code (`parse_type_maps`)

### `wrapper.gleam`
- Modify `generate_module_wrapper` signature to accept the set of available type declaration files (pre-scanned by the caller as a `Set(#(String, String))` of `#(package, module)` pairs)
- Modify `type_to_ts` to accept the available declarations set:
  - Non-prelude named types with a matching declaration file → emit type name (import will be generated)
  - Non-prelude named types without a declaration file → emit `unknown`
- Modify `generate_dts` to collect non-prelude type references from wrapped function signatures and generate `import type` statements for types with matching declaration files
- New function: `collect_non_prelude_named_types` — walks type trees and returns all `Named` types not matched by steps 1–3 of the resolution chain
- Extend `WrapperResult` to include a `warnings: List(String)` field for types that resolved to `unknown`

### `output.gleam`
- New function to copy type declaration `.d.ts` files from the source directory to `dist/_types/` in the output
- Generate empty `.mjs` stubs alongside each copied `.d.ts`
- Only copy/generate files that are actually referenced by wrapper modules

### `talc.gleam`
- Scan the type declarations directory before wrapper generation to build the set of available declaration files
- Wire `type_declarations_dir` config and available declarations through to `wrapper.generate_module_wrapper`
- Collect and surface warnings from wrapper generation

### Tests

- Function with external type that has a matching declaration → proper import and type name in `.d.ts`
- Function with external type, no declaration file → `unknown` in `.d.ts`
- Parameterized external type (e.g., `Subject<T>`) → type name with generic args in `.d.ts`
- Mixed: function with prelude types, Result, and external types in same signature
- Config: custom `type_declarations_dir` path
- Config: `type_maps` removal (no regression)
- Output: type declaration files and `.mjs` stubs copied to `dist/_types/`

## Future Improvements

- **npm `@gleam-types/` packages**: Community-maintained type declaration packages, discovered in `node_modules`. talc would check local `talc-types/` first, then `node_modules/@gleam-types/{package}`.
- **`gleam_package_interface` support**: When upstream exposes `@external` annotation data, talc can use it as an additional resolution step (between step 3 and step 4 above).
- **Same-package custom types**: Automatically import same-package custom types from the native `.d.mts` files in wrapper `.d.ts`, without requiring type declaration files. Requires understanding Gleam's `$` suffix naming convention in `.d.mts`.
- **Auto-generation**: A `talc init-types` command that scans the package interface for external types and generates skeleton `.d.ts` files.
