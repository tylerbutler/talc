# gleam_npm — npm Publishing Tool for Gleam Libraries (Historical PRD)

> **Note:** This document is the original pre-implementation product requirements spec. It was
> written before the tool was built and uses the working name `gleam_npm` (the package shipped
> as `talc`). Several details no longer match the current implementation:
>
> - The tool is named **talc**, not `gleam_npm`.
> - The config file is **`talc.ccl`** (CCL format), not `gleam_npm.toml`.
> - TypeScript declarations are **not generated** by talc. The Gleam compiler emits `.d.mts`
>   files alongside `.mjs` when `[javascript] typescript_declarations = true` is set in
>   `gleam.toml`; talc copies those compiler-produced files verbatim.
> - The CLI is invoked as `gleam run -m talc -- <command>`, not `gleam_npm <command>`.
> - `engines.node` is not emitted in the generated `package.json`.
> - The Phase 2 `.d.ts` generation pipeline (IR, type mapper, ADT emitter) was replaced by
>   directly copying the compiler's `.d.mts` output.
> - Watch mode (Phase 3) was not implemented.
> - JSON Schema generation (Phase 3 bonus) was not implemented.
>
> For the current design, see [README.md](./README.md) and [CLAUDE.md](./CLAUDE.md).

**Version:** 1.0 | **Status:** Historical | **Date:** March 2025

-----

## 1. Overview

### 1.1 Problem Statement

Gleam compiles to JavaScript but provides no tooling to package that output for the npm ecosystem. Gleam developers who want to publish libraries for JavaScript and TypeScript consumers must manually author `package.json` files, maintain type declarations, and wire up module entry points — none of which Gleam’s build system produces. There is no established convention or tool for this workflow.

The result is that Gleam libraries are effectively inaccessible to the JavaScript community, and Gleam developers targeting JS runtimes cannot easily share their work beyond the Gleam ecosystem.

### 1.2 Vision

Build a CLI tool that reads a compiled Gleam project and produces a publish-ready npm package directory: a well-formed `package.json` derived from `gleam.toml` metadata, and TypeScript declaration files (`.d.ts`) generated from public Gleam types. The tool bridges Gleam’s type system to TypeScript’s, enabling type-safe consumption of Gleam libraries from JavaScript and TypeScript without manual maintenance.

### 1.3 Success Criteria

- A Gleam developer can publish a properly-structured npm package with a single command
- TypeScript consumers receive accurate type information for all public Gleam API surface
- Generated `package.json` satisfies npm’s package validation and follows modern ESM conventions
- The tool handles the full Gleam type system: primitives, records, custom types (ADTs), generics, and Result/Option
- Adopted by at least 3 prominent Gleam JS-target libraries within 6 months of release

-----

## 2. Target Users

|User Type           |Needs                              |Example                                  |
|--------------------|-----------------------------------|-----------------------------------------|
|Gleam Library Author|Automated metadata + types         |Publishing a utility library to npm      |
|Framework Developer |Full type coverage, reliable output|Exposing Gleam HTTP primitives to JS devs|
|JS/TS Consumer      |Accurate .d.ts, proper ESM exports |Using a Gleam library in a Vite project  |

### 2.1 User Stories

- **Library author:** I want to run a single command after `gleam build` that produces an npm-ready directory so I can publish without writing any JSON or TypeScript by hand.
- **TypeScript consumer:** I want to install a Gleam library from npm and get full type safety and autocomplete in my editor without extra setup.
- **CI/CD pipeline:** I want to integrate gleam_npm into my GitHub Actions workflow so every tagged release automatically publishes to npm with the correct version and metadata.

-----

## 3. Goals and Non-Goals

### 3.1 Goals

|Priority|Goal                         |Description                                                                                                |
|--------|-----------------------------|-----------------------------------------------------------------------------------------------------------|
|P0      |package.json generation      |Derive name, version, description, license, repository, and ESM export fields from gleam.toml              |
|P0      |.d.ts generation — primitives|Emit TypeScript declarations for pub functions using primitive types (Int, Float, String, Bool)            |
|P0      |.d.ts generation — records   |Emit TypeScript interfaces for pub Gleam record types                                                      |
|P1      |.d.ts generation — ADTs      |Emit tagged union types for custom types with multiple constructors                                        |
|P1      |.d.ts generation — generics  |Correctly emit TypeScript generics from Gleam type parameters                                              |
|P1      |Result and Option mapping    |Map `Result(a, e)` to `{ ok: true; value: a } | { ok: false; error: e }` and `Option(a)` to `a | undefined`|
|P1      |Overrides via config         |Allow `gleam_npm.toml` sidecar to override any generated field                                             |
|P2      |Multi-module support         |Handle packages with multiple pub modules and generate sub-path exports                                    |
|P2      |pack / publish commands      |Wrap `npm pack` / `npm publish` for a complete publishing workflow                                         |
|P2      |Watch mode                   |Re-generate on gleam build changes for development iteration                                               |

### 3.2 Non-Goals

- **Bundling** — the tool packages Gleam’s compiled `.mjs` output as-is; bundling is left to downstream tooling (esbuild, rollup)
- **JavaScript FFI declarations** — types for Gleam FFI (`.mjs`) files are out of scope
- **Erlang target packaging** — this tool is exclusively for the JavaScript compilation target
- **Runtime behavior** — no polyfills, shims, or Gleam runtime modifications
- **Package registry other than npm** — Hex.pm publishing is handled by the Gleam CLI

-----

## 4. Functional Requirements

### 4.1 CLI Interface

```
gleam_npm generate    # generate package.json + .d.ts files
gleam_npm pack        # generate + run npm pack
gleam_npm publish     # generate + run npm publish
gleam_npm check       # validate output without writing files
```

All commands read from the current working directory (expected to be a Gleam project root) and write output to `./npm_dist/` by default. Output directory is configurable.

### 4.2 package.json Generation

#### FR-1: Metadata from gleam.toml

|gleam.toml field          |package.json field                             |
|--------------------------|-----------------------------------------------|
|`name`                    |`name` (with optional scope prefix from config)|
|`version`                 |`version`                                      |
|`description`             |`description`                                  |
|`licences[0]`             |`license`                                      |
|`repository.url`          |`repository`                                   |
|`gleam_version` constraint|`engines.node` (mapped conservatively)         |

#### FR-2: ESM Export Fields

```json
{
  "type": "module",
  "main": "./dist/mylib.mjs",
  "module": "./dist/mylib.mjs",
  "types": "./dist/mylib.d.ts",
  "exports": {
    ".": {
      "import": "./dist/mylib.mjs",
      "types": "./dist/mylib.d.ts"
    }
  }
}
```

The entry point filename is inferred from the package’s primary public module. If multiple public modules exist, sub-path exports are generated for each.

#### FR-3: gleam_npm.toml Overrides

A `gleam_npm.toml` file in the project root allows authors to override or extend any generated field. Supports: npm scope prefix, additional `package.json` fields (keywords, homepage, bugs, funding), peer dependencies, custom output directory, and npm registry URL for private registries.

```toml
[package]
scope = "@myorg"
registry = "https://registry.npmjs.org"
output_dir = "npm_dist"

[package.json]
keywords = ["gleam", "functional"]
homepage = "https://example.com"

[peer_dependencies]
react = ">=18"
```

### 4.3 TypeScript Declaration Generation

#### FR-4: Type System Mapping

|Gleam Type          |TypeScript Type                                                                       |Notes                    |
|--------------------|--------------------------------------------------------------------------------------|-------------------------|
|`Int`               |`number`                                                                              |                         |
|`Float`             |`number`                                                                              |                         |
|`String`            |`string`                                                                              |                         |
|`Bool`              |`boolean`                                                                             |                         |
|`Nil`               |`undefined`                                                                           |                         |
|`List(a)`           |`Array<A>`                                                                            |Type parameter propagated|
|`Option(a)`         |`A | undefined`                                                                       |Unwrapped for ergonomics |
|`Result(a, e)`      |`{ readonly ok: true; readonly value: A } | { readonly ok: false; readonly error: E }`|                         |
|`BitArray`          |`Uint8Array`                                                                          |                         |
|Custom type (record)|`interface`                                                                           |Single-constructor types |
|Custom type (ADT)   |discriminated union                                                                   |Multi-constructor types  |
|Generic type param  |TypeScript generic                                                                    |e.g. `fn foo(a: a) -> a` |

#### FR-5: ADT Representation

Gleam’s compiled JS runtime represents custom type constructors as objects with a specific shape. The tool generates TypeScript types that match this runtime representation:

```gleam
// Gleam source
pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}
```

```typescript
// Generated .d.ts
export interface Circle {
  readonly [Symbol.for("gleam_type")]: "Circle";
  readonly radius: number;
}
export interface Rectangle {
  readonly [Symbol.for("gleam_type")]: "Rectangle";
  readonly width: number;
  readonly height: number;
}
export type Shape = Circle | Rectangle;
```

#### FR-6: Public Function Declarations

```gleam
// Gleam source
pub fn add(a: Int, b: Int) -> Int
pub fn map(list: List(a), f: fn(a) -> b) -> List(b)
```

```typescript
// Generated .d.ts
export declare function add(a: number, b: number): number;
export declare function map<A, B>(list: Array<A>, f: (a: A) => B): Array<B>;
```

#### FR-7: Source Analysis Strategy

Declaration generation uses `gleam export package-interface` as the primary source of truth — see Section 8 for full rationale. The tool will:

- Invoke `gleam export package-interface` to obtain the typed, resolved interface JSON
- Consume it using the `gleam_package_interface` hex.pm library
- Emit warnings for any pub API that cannot be mapped (e.g. opaque types, FFI-backed types)

### 4.4 Output Structure

```
npm_dist/
├── package.json         # generated
├── README.md            # copied from project root if present
├── LICENSE              # copied from project root if present
└── dist/
    ├── mylib.mjs        # copied from build/dev/javascript/
    └── mylib.d.ts       # generated
```

-----

## 5. Type System Edge Cases

|Scenario              |Handling                                                               |
|----------------------|-----------------------------------------------------------------------|
|Opaque types          |Emit as opaque interface (no fields exposed); emit warning to author   |
|Recursive types       |Detect cycles and emit with TypeScript interface self-reference        |
|Type aliases          |Expand inline; no TypeScript type alias emitted (implementation detail)|
|Phantom types         |Type parameter retained in signature even if unused at runtime         |
|Functions as arguments|Emit as TypeScript function type `(a: A) => B`                         |
|Tuples                |Emit as `[A, B]` readonly tuple type                                   |
|Dynamic / Any         |Emit as `unknown` with a comment noting the dynamic origin             |

-----

## 6. Implementation Phases

### Phase 1: package.json Generation (MVP)

- Read `gleam.toml` and extract all mappable metadata
- Generate valid `package.json` with ESM export fields
- Copy compiled `.mjs` files from `build/` to output directory
- Copy `README.md` and `LICENSE` if present
- `gleam_npm.toml` override support for scope and extra fields
- `gleam_npm check` command for dry-run validation

**Deliverable:** A Gleam library author can produce and publish a valid npm package without writing any `package.json` by hand.

### Phase 2: TypeScript Declaration Generation

- Invoke `gleam export package-interface` to obtain the typed, resolved package interface JSON
- Type mapper for all primitive and standard library types using interface JSON
- Record type → TypeScript interface generation
- ADT → discriminated union generation with Gleam runtime tag shape
- Generic type parameter propagation
- `Result(a, e)` and `Option(a)` canonical mappings
- Warning system for unmappable types (opaque, FFI-backed)

**Deliverable:** TypeScript consumers of Gleam libraries get accurate autocomplete and type checking with no manual `.d.ts` authoring.

### Phase 3: Workflow Integration + JSON Schema

- `gleam_npm pack` wrapping `npm pack`
- `gleam_npm publish` wrapping `npm publish` with pre-flight checks
- Multi-module packages with sub-path exports
- Watch mode for development iteration
- GitHub Actions example workflow
- Provenance attestation support (`npm --provenance`)
- JSON Schema output (`schema.json`) as a bonus artifact from the same type mapping pipeline — useful for runtime validation (AJV) and OpenAPI documentation

**Deliverable:** Complete end-to-end publishing workflow suitable for CI/CD.

-----

## 7. AST and Type Tooling Landscape

This section documents the available tools for working with Gleam’s type system, resolving the approach for how gleam_npm extracts type information. The conclusion is clear: use the official package interface JSON.

### 7.1 `gleam export package-interface` (RECOMMENDED)

The Gleam compiler has a built-in command that produces a fully-resolved, typed JSON description of the entire public API:

```bash
gleam export package-interface
# Output: build/dev/docs/<package>/package-interface.json

# Also produced automatically by:
gleam docs build
```

The package interface JSON contains: all public type definitions (fully resolved, not aliases), public functions with parameter names and types, public constants, documentation strings, and type parameters. This is the compiler’s own typed representation — aliases are expanded, imports traced, generics resolved.

The `gleam_package_interface` hex.pm library (`gleam-lang/package-interface`) provides Gleam types and a decoder for consuming this JSON from within a Gleam program, making it straightforward to build gleam_npm as a Gleam library that reads and transforms this data.

### 7.2 `glance` — Source-Level AST Parser

`glance` is a Gleam source code parser written in Gleam. It parses `.gleam` source files into an untyped AST and is used by code generation tools, linters, and documentation tools across the ecosystem.

**Limitations for gleam_npm:** glance produces an untyped AST. Type aliases are not resolved across module boundaries, and imported types are not traced to their definitions. This makes it unsuitable as the primary source of type information for `.d.ts` generation. It could serve as a fallback for extracting doc comments or source positions not present in the package interface, but should not be the primary tool.

### 7.3 `glimpse` — Multi-Module Typechecker (Future)

`glimpse` wraps glance with multi-module awareness and experimental typechecking. Its stated goal is to handle the common parts of Gleam compilation so that developers targeting different output languages can focus on codegen. However, typechecking is not yet fully implemented and it is not suitable for production use in gleam_npm at this time. Worth monitoring as the project matures.

### 7.4 Tool Selection Decision

|Tool                            |Role in gleam_npm                                                                         |
|--------------------------------|------------------------------------------------------------------------------------------|
|`gleam export package-interface`|**PRIMARY:** source of all type information for .d.ts generation                          |
|`gleam_package_interface` (hex) |Gleam decoder types for consuming the package interface JSON                              |
|`glance`                        |**FALLBACK ONLY:** doc comment extraction if needed beyond what package interface provides|
|`glimpse`                       |**NOT YET:** monitor for future use if cross-module analysis needs arise                  |

-----

## 8. JSON Schema Round-Trip Analysis

A proposed alternative approach was to generate JSON Schema from Gleam types, then use the well-established `json-schema-to-typescript` npm package to produce `.d.ts` files. This section evaluates that approach.

### 8.1 The Toolchain

The JS ecosystem has mature tooling for JSON Schema → TypeScript:

- **`json-schema-to-typescript`:** Compiles JSON Schema to TypeScript typings; handles objects, enums as string literal unions, required/optional, `$ref` definitions, and generics.
- **`ts-json-schema-generator`:** Goes the other direction (TypeScript → JSON Schema); irrelevant here but shows the ecosystem is bidirectional.
- **`jtd-codegen`:** JSON Typedef (a simpler, stricter alternative to JSON Schema) → TypeScript; produces clean discriminated unions.

### 8.2 Why the Round-Trip Doesn’t Work for .d.ts Generation

The fundamental problem is that Gleam’s compiled JavaScript uses class-based runtime representations with a specific tag shape:

```javascript
// Gleam ADT compiled to JS (actual runtime shape)
class Circle extends CustomType {
  constructor(radius) { super(); this.radius = radius; }
}

// Tag used for pattern matching:
Circle.prototype[Symbol.for("gleam_type")] = "Circle"
```

JSON Schema has no mechanism to encode this Gleam-specific tag pattern. A round-trip through JSON Schema would produce structurally plausible TypeScript, but the discriminator field names would be wrong — a TypeScript consumer checking the discriminator or using `instanceof` would get incorrect behavior. The generated types would be misleading rather than helpful.

Additionally, JSON Schema cannot express function types at all, meaning public function signatures would be lost entirely.

### 8.3 Where JSON Schema IS Valuable (Phase 3 Bonus)

JSON Schema is worth generating as a secondary artifact — not as a step in the `.d.ts` pipeline, but as a standalone deliverable from the same type mapping logic:

- Runtime validation of data that crosses the Gleam/JS boundary (via AJV or similar)
- OpenAPI / Swagger documentation generation for Gleam HTTP services
- Consumers in languages other than TypeScript that have JSON Schema tooling
- Form generation and data validation in frontend frameworks

The `schema.json` generation would be a second formatter applied to the same intermediate representation that produces `.d.ts`, added in Phase 3. It would use `oneOf` with a properties-based discriminator rather than attempting to encode the Gleam class tag, producing schemas useful for validation even if they don’t perfectly mirror the runtime representation.

### 8.4 Architecture Implication

This analysis suggests a clean two-stage architecture:

```
package-interface.json
        |
        v
  [Intermediate IR]   <-- language-agnostic type representation
     /         \
    v           v
 .d.ts       schema.json   (Phase 3)
(precise)    (approximate, for validation use cases)
```

The intermediate representation is gleam_npm’s own type model, derived from the package interface. Both output formatters consume it independently, keeping the type mapping logic centralized.

-----

## 9. Open Questions

### 9.1 Library Name

|Name       |Notes                                                                |
|-----------|---------------------------------------------------------------------|
|`gleam_npm`|Descriptive, clear purpose; follows gleam_ library convention        |
|`npm_gleam`|Reversed convention; less idiomatic                                  |
|`gleem`    |Short, memorable; not obviously related to npm                       |
|`shard`    |Evocative of package distribution; available on hex.pm as of research|

**Recommendation:** `gleam_npm` for clarity; worth checking hex.pm and npm availability.

### 9.2 Distribution Method

The tool itself needs to be distributed. Options:

- As a Gleam library with a main module (run via `gleam run -m gleam_npm`)
- As a standalone binary distributed via GitHub Releases
- As an npm package (meta: a JS tool for packaging Gleam)

**Recommendation:** Primary distribution as a Gleam library on hex.pm; provide a pre-built binary as a convenience for CI.

-----

## 10. Success Metrics

|Metric            |Target                                                                        |
|------------------|------------------------------------------------------------------------------|
|Adoption          |3+ prominent Gleam JS libraries using gleam_npm within 6 months               |
|Type coverage     |100% of primitive and record types; >90% of ADT types handled without warnings|
|npm validation    |Zero npm publish failures attributable to generated package.json              |
|Community feedback|Positive reception in Gleam Discord #packages channel                         |
|Maintenance       |Compatible with each Gleam minor release within 2 weeks of release            |

-----

## Appendix A: Type Mapping Reference

|Gleam Module   |Gleam Type    |TypeScript Type                                   |
|---------------|--------------|--------------------------------------------------|
|`gleam`        |`Int`         |`number`                                          |
|`gleam`        |`Float`       |`number`                                          |
|`gleam`        |`String`      |`string`                                          |
|`gleam`        |`Bool`        |`boolean`                                         |
|`gleam`        |`Nil`         |`undefined`                                       |
|`gleam`        |`List(a)`     |`Array<A>`                                        |
|`gleam`        |`BitArray`    |`Uint8Array`                                      |
|`gleam/option` |`Option(a)`   |`A | undefined`                                   |
|`gleam/result` |`Result(a, e)`|`{ ok: true; value: A } | { ok: false; error: E }`|
|`gleam/dict`   |`Dict(k, v)`  |`Map<K, V>`                                       |
|`gleam/set`    |`Set(a)`      |`Set<A>`                                          |
|`gleam/dynamic`|`Dynamic`     |`unknown`                                         |

-----

## Appendix B: Example Output

**Input: gleam.toml**

```toml
name = "gleam_utils"
version = "1.0.0"
description = "Utility functions for Gleam"
licences = ["Apache-2.0"]

[repository]
type = "github"
user = "myorg"
repo = "gleam_utils"
```

**Output: package.json**

```json
{
  "name": "gleam_utils",
  "version": "1.0.0",
  "description": "Utility functions for Gleam",
  "license": "Apache-2.0",
  "type": "module",
  "main": "./dist/gleam_utils.mjs",
  "types": "./dist/gleam_utils.d.ts",
  "exports": {
    ".": {
      "import": "./dist/gleam_utils.mjs",
      "types": "./dist/gleam_utils.d.ts"
    }
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/myorg/gleam_utils"
  }
}
```