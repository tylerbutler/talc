# talc MVP

## Goal

A Gleam library author can turn a JavaScript build into an npm package.
JavaScript and TypeScript consumers use the native API that Gleam compiles.
talc assembles package files and metadata; the Gleam compiler defines runtime
values and types.

## Inputs and workflow

Authors use Gleam 1.16 or later, enable
`[javascript] typescript_declarations = true` in `gleam.toml`, and run
`gleam build --target javascript` before packaging.

Gleam 1.16 copies external type declaration files into its JavaScript build.
The MVP reads that build output; it does not add a source-copy fallback for
older compilers.

| Command | Responsibility |
| --- | --- |
| `check` | Report metadata/configuration validation; use the package interface for root-module validation when available. |
| `generate` | Read metadata and public module names, generate `package.json`, and copy build artifacts into `npm_dist/`. |
| `pack` | Generate output and call `npm pack`. |
| `publish` | Generate output and call `npm publish` with explicit publish options. |

Keep `talc.ccl` optional. Retain npm scope, output directory, registry,
`package.json` overrides, and explicit peer dependencies. Keep lifecycle
scripts disabled unless the author opts in through `unsafe_allow_scripts`.

`check` is a configuration report, not a full runtime or TypeScript check.
Authors must build and exercise the generated package before publishing.

## Package contract

Copy `.mjs` and `.d.mts` files without modification. Include local `.js` and
`.d.ts` FFI artifacts, private modules, the Gleam support module, and prelude
files. Copy dependency JavaScript and declaration artifacts next to `dist/`
so relative imports still resolve.

Use the package-named public module as the default root entry point. Generate
sub-path exports for other public modules, with the package-name prefix
removed. Export `./gleam` for the compiler's native interop functions.
List `types` before `import` in each export condition. Keep internal modules
and dependency modules out of automatic public exports.
Reject a public `<package>/gleam` module that conflicts with the reserved
interop export, unless the author supplies an explicit `exports` override.

Require `.mjs` and `.d.mts` artifacts for each public module and the Gleam
support module, plus the prelude files. Report missing artifacts instead of
generating replacement types. Preserve existing explicit metadata overrides.

Copy `README.md`, `LICENSE`, `LICENSE-MIT`, and `LICENSE-APACHE` when available,
without changing their bytes. Missing assets are valid; report inspection and
copy failures for present assets.

Use a single `gleam.toml` licence as npm `license` metadata. For multiple
licences, require an explicit `package.json.license` override in `talc.ccl`.
The author supplies the intended SPDX expression or npm license reference;
talc does not choose OR/AND terms. Preserve explicit overrides.

Require a non-root relative output path using forward slashes. Reject absolute,
drive-qualified, UNC, backslash, parent-traversal, NUL, and trailing-dot/space
path forms. Reject symbolic links in output components and output trees,
including dangling links, and reject multiply linked files. Do not follow links
while scanning build artifacts or selected assets.

Plan the output and check existing files before writing. Reject obsolete
JavaScript/declaration artifacts and selected assets with instructions to choose
fresh output. Preserve user files; do not reconcile or delete unowned output.
Repeat generation remains valid when existing artifacts belong to the current
plan. `pack` and `publish` stop when generation fails.

Missing optional configuration retains defaults. Reject malformed present
configuration values and `licences` arrays instead of dropping entries. Keep
interface command, timeout, read, and decode reasons in `check` reports without
claiming interface validation succeeded. Preserve npm error reporting.

## JavaScript and TypeScript boundary

Follow [Gleam's externals guidance](https://gleam.run/documentation/externals/),
especially its sections on JavaScript data and API design.

Gleam recommends designing APIs with its type system and minimizing externals.
For talc, this means preserving the author's Gleam API rather than generating
a second API with different values.

Consumers use the compiler's documented constructors, predicates, and
accessors. For example, `Result$Ok`, `Result$isOk`, and `Result$Ok$0` come from
`<package>/gleam`. Custom-type helpers come from the public module that
defines the type. Lists and options remain Gleam values; they do not become
JavaScript arrays or `undefined`.

The compiler cannot verify external implementation behavior. Authors must
provide correct signatures and external declarations, test FFI boundaries,
and declare npm packages used by bare imports. talc preserves those files
and declarations but does not infer npm dependencies or inspect external
code. Authors can add npm `dependencies` through `package.json` overrides.

If consumers need standard-library operations such as Option helpers, the
author supplies a public module with the relevant operations or explicit
exports. The MVP does not expose dependency packages through wildcards.

## Removal and migration

Remove the true-myth wrapper generator, wrapper metadata loader, declaration
parser, wrapper export routing, and automatic true-myth peer dependency.
Retain the package-interface loader for public module discovery.

Reject `package.use_true_myth` with instructions to remove it. Reject an
output directory containing `dist/_wrapper` before writing package files.
Ask authors to remove the legacy directory or select fresh output; do not
delete user files.

This changes the consumer API for packages that used wrappers. Authors must
choose an appropriate release version and update consumers to native values.
Explicit peer dependencies remain under author control, including true-myth
if other code still needs it.

## Acceptance criteria

- Unit tests cover native exports, metadata overrides, explicit dependencies,
  required artifacts, copied private/FFI files, and migration errors.
- An npm tarball installs into a separate consumer directory without
  true-myth.
- Consumers import the root, a public submodule, and `./gleam` by package name;
  internal modules have no automatic export.
- Runtime checks cover Result success/error, Result parameters, Option
  returns, custom-type construction/access, external types, and local FFI
  through a private module.
- TypeScript in strict NodeNext mode resolves installed declarations and
  rejects incorrect primitive, Result, and external-type arguments.
- Installed JavaScript, FFI, and declaration files match build artifacts.

## Excluded from the MVP

No conversion wrappers, generated TypeScript types, bundling, tree shaking,
CommonJS build, watch mode, or schema generation. Copy the build artifacts
rather than adding an import-graph analyzer. This can include unused modules
and dependencies.

The integration target is Node.js ESM. Browser bundlers, Deno, and Bun need
separate checks before talc claims support. Non-code FFI assets and automatic
validation of bare npm imports are outside this MVP.
