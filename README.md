# talc

[![Package Version](https://img.shields.io/hexpm/v/talc)](https://hex.pm/packages/talc)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/talc/)

npm packaging tool for Gleam libraries. Reads a compiled Gleam project and produces a
publish-ready npm package directory with:

- a generated `package.json` derived from `gleam.toml`
- compiled `.mjs` files copied from `build/dev/javascript`
- Gleam compiler-generated `.d.mts` declarations copied from the same build
- dependency JS artifacts placed next to `dist/` for runtime imports
- local JavaScript FFI files and private modules needed by public functions

The MVP packages native Gleam output without API or type conversion. See
[PRD.md](./PRD.md) for the scope and acceptance criteria.

Requires Gleam 1.16 or later so the JavaScript build includes external type
declaration files.

## Installation

```sh
gleam add --dev talc
```

## Usage

From a Gleam project root with JavaScript declarations enabled:

```toml
[javascript]
typescript_declarations = true
```

Build the project for JavaScript before running talc:

```sh
# Build the project for JavaScript
gleam build --target javascript

# Validate configuration without writing files
gleam run -m talc -- check

# Generate npm package in npm_dist/
gleam run -m talc -- generate

# Generate and create a tarball (runs npm pack)
gleam run -m talc -- pack

# Generate and publish to npm (runs npm publish)
gleam run -m talc -- publish

# Publish with options
gleam run -m talc -- publish --dry-run=true              # dry run
gleam run -m talc -- publish --tag=beta                  # publish under a dist-tag
gleam run -m talc -- publish --access=public             # set access level
gleam run -m talc -- publish --provenance=true           # provenance attestation (CI only)

# Use a custom output directory
gleam run -m talc -- generate --output-dir my_output
```

### Output Structure

```
npm_dist/
├── package.json              # Generated from gleam.toml
├── README.md                 # Copied from project root (if present)
├── LICENSE                   # Copied from project root (if present)
├── prelude.mjs               # Gleam runtime prelude
├── prelude.d.mts             # Gleam runtime prelude types
├── gleam_stdlib/             # Dependency JS artifacts (for runtime imports)
│   └── ...
└── dist/
    ├── gleam.mjs             # Gleam support file
    ├── gleam.d.mts           # Gleam support types
    ├── mylib.mjs             # Compiled JS from build/dev/javascript
    ├── mylib.d.mts           # Compiler-generated TypeScript declarations
    └── ...                  # Private modules and local FFI artifacts
```

### TypeScript Support

talc copies Gleam's own `.d.mts` declaration files produced by the compiler
(via `[javascript] typescript_declarations = true` in `gleam.toml`). Because
the compiler generates both the `.mjs` and `.d.mts` files together, the
declarations are always accurate — no separate generation step.

Multi-module packages receive sub-path exports in `package.json` for each
public module. The `./gleam` export provides the compiler's interop functions.
Each export lists `types` before `import` for TypeScript module resolution.
The automatic `./gleam` export is reserved. If you have a public module named
`<package>/gleam`, rename it or supply an explicit `package.json.exports`
override in `talc.ccl`.

### Native JavaScript interop

Use the functions in [Gleam's externals documentation](https://gleam.run/documentation/externals/#gleam-data-in-javascript)
to construct and inspect native values. For a library named `mylib` with a
`parse_positive` function:

```js
import { parse_positive } from "mylib";
import { Result$isOk, Result$Ok$0, Result$Error$0 } from "mylib/gleam";

const result = parse_positive("42");
if (Result$isOk(result)) {
  console.log(Result$Ok$0(result));
} else {
  console.error(Result$Error$0(result));
}
```

For your public custom types, import compiler-generated constructors and
accessors from the module that defines the type, such as `Person$Person` and
`Person$Person$name`. Do not depend on undocumented object fields.

talc preserves local `.mjs`, `.js`, `.d.mts`, and `.d.ts` artifacts and their
relative paths, including private modules. It only exports public modules and
`./gleam`. It does not check external implementations or create declarations
for them. Authors must supply correct external type declarations and declare
npm dependencies used by bare imports through `package.json` overrides or
`peer_dependencies` in `talc.ccl`.

Dependency modules such as `gleam/option` remain package implementation
details. If consumers need their constructors or helpers, provide a public
Gleam module that re-exports the required operations, or configure explicit
exports. talc does not add dependency export wildcards.

### Migration from true-myth

Remove `package.use_true_myth` from `talc.ccl`, whether its value is `true` or
`false`. talc rejects this removed option with a migration error. Update
consumers to use native Gleam values and helpers instead of true-myth values.
Remove any true-myth dependency that you no longer use.

Use a fresh output directory or remove the old `dist/_wrapper` directory
before generating. talc rejects output directories that still contain that
directory so that npm does not publish stale wrappers. It does not delete
existing output for you.

### Configuration

`talc` reads metadata from your `gleam.toml` automatically. To customize the npm package,
create a `talc.ccl` in your project root:

```ccl
package =
  scope = @myorg
  output_dir = npm_dist
  registry = https://registry.npmjs.org

package.json =
  homepage = https://example.com
  private = true
  keywords =
    = gleam
    = functional

peer_dependencies =
  react = >=18
```

#### Output safety and repeat generation

Use a non-empty relative output path with forward slashes, such as `npm_dist`
or `packages/npm`. talc rejects project-root aliases, absolute paths, Windows
drive/UNC forms, backslashes, `..` components, NUL characters, and components
ending in a dot or space (except `.`). It rejects symlinks in output paths and
output trees, including links inside the project, and multiply linked files.
Build artifacts and selected assets must also use ordinary files/directories.
These checks do not protect against another process replacing paths during a
write and do not establish Windows runtime support.

You can generate into unchanged output again. If removed modules, dependencies,
or selected assets leave obsolete files, talc stops before writing and asks you
to choose a fresh directory. It does not delete files. Move user files yourself;
an extra `.mjs`, `.js`, `.d.mts`, or `.d.ts` file can also trigger this refusal.
`pack` and `publish` do not invoke npm if generation fails.

#### Licences and input errors

talc copies `README.md`, `LICENSE`, `LICENSE-MIT`, and `LICENSE-APACHE` from the
project root without changing their bytes. Missing files are valid. Failures to
inspect or copy present assets are errors.

A single entry in `gleam.toml` `licences` supplies npm `license` metadata.
Multiple entries require an explicit `license` field under `package.json` in
`talc.ccl`. Set the project's intended SPDX expression or npm-supported
`SEE LICENSE IN <filename>` reference. talc does not infer OR/AND terms or
change explicit overrides.

Missing optional configuration retains its defaults. Present package options
and peer dependency values must have the expected types; malformed values and
non-string `licences` entries are errors. `check` reports the specific reason
when it cannot load the package interface. It remains a metadata/configuration
report and does not check runtime behavior or TypeScript consumers.

#### Registry Behaviour

- `package.registry` emits a `publishConfig.registry` field in the generated `package.json`.
- The `publish` command passes `--registry <url>` to npm unless the user has set a
  `publishConfig` key in `package.json` extra fields (explicit override takes precedence).
- An empty registry string is ignored when generating `package.json` and rejected by the
  `publish` command if it would be used to build flags.

### CI/CD Integration

Example GitHub Actions workflow for automated npm publishing on release:

```yaml
name: Publish to npm
on:
  release:
    types: [published]

permissions:
  contents: read
  id-token: write  # required for --provenance

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Erlang & Gleam
        uses: erlef/setup-beam@v1
        with:
          otp-version: "27"
          gleam-version: "1.16"

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          registry-url: "https://registry.npmjs.org"

      - name: Build Gleam project
        run: gleam build --target javascript

      - name: Publish npm package
        run: gleam run -m talc -- publish --provenance=true
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```
