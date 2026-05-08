# talc

[![Package Version](https://img.shields.io/hexpm/v/talc)](https://hex.pm/packages/talc)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/talc/)

npm packaging tool for Gleam libraries. Reads a compiled Gleam project and produces a
publish-ready npm package directory with:

- a generated `package.json` derived from `gleam.toml`
- compiled `.mjs` files copied from `build/dev/javascript`
- Gleam compiler-generated `.d.mts` declarations copied from the same build
- dependency JS artifacts placed next to `dist/` for runtime imports
- optional true-myth wrapper modules for top-level `Result` and `Option` types

## Installation

```sh
gleam add --dev talc
```

## Usage

From a Gleam project root (after running `gleam build --target javascript`):

```sh
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
    └── _wrapper/             # Optional true-myth wrappers (when use_true_myth = true)
        ├── mylib.mjs         # Wrapper module converting Result/Option to true-myth
        └── mylib.d.ts        # Wrapper type declarations
```

### TypeScript Support

talc copies Gleam's own `.d.mts` declaration files produced by the compiler
(via `[javascript] typescript_declarations = true` in `gleam.toml`). Because
the compiler generates both the `.mjs` and `.d.mts` files together, the
declarations are always accurate — no separate generation step.

Multi-module packages receive sub-path exports in `package.json` for each
public module.

### true-myth Wrappers

When `use_true_myth = true` (the default), talc generates thin wrapper modules
for any public module whose functions have top-level `Result` or `Option` in
their parameter or return types. These wrappers convert to/from
[true-myth](https://true-myth.js.org/) `Result` and `Maybe` types for a more
ergonomic TypeScript API.

- Only modules that actually use `Result`/`Option` get a wrapper; others are
  skipped.
- `true-myth` is added as a `peerDependency` only when at least one wrapper is
  generated.
- Set `use_true_myth = false` in `talc.ccl` to disable wrapper generation
  entirely.

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
          gleam-version: "1.14"

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
