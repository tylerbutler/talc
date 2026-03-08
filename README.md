# talc

A Gleam CLI tool.
=======
[![Package Version](https://img.shields.io/hexpm/v/talc)](https://hex.pm/packages/talc)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/talc/)

npm packaging tool for Gleam libraries. Reads a compiled Gleam project and produces a
publish-ready npm package directory with a generated `package.json` and TypeScript `.d.ts`
declarations.

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
├── package.json         # Generated from gleam.toml
├── README.md            # Copied from project root (if present)
├── LICENSE              # Copied from project root (if present)
└── dist/
    ├── mylib.mjs        # Compiled JS files from build output
    ├── mylib.d.ts       # Generated TypeScript declarations
    └── mylib/
        ├── module.mjs   # Sub-module JS
        └── module.d.ts  # Sub-module declarations
```

### TypeScript Support

talc automatically generates `.d.ts` files for all public modules using the
Gleam compiler's package interface. The generated types match Gleam's JavaScript
runtime representation:

- Primitive types → `number`, `string`, `boolean`, `undefined`
- `List(a)` → `Array<A>`, `Option(a)` → `A | undefined`
- `Result(a, e)` → discriminated `{ ok: true; value: A } | { ok: false; error: E }`
- Record types → TypeScript `interface`
- ADTs → discriminated unions with `Symbol.for("gleam_type")` tags
- Generic type parameters → TypeScript generics
- Multi-module packages → sub-path exports in package.json

### Configuration

`talc` reads metadata from your `gleam.toml` automatically. To customize the npm package,
create a `talc.toml` in your project root:

```toml
[package]
scope = "@myorg"           # npm scope prefix
output_dir = "npm_dist"    # output directory (default: npm_dist)
registry = "https://registry.npmjs.org"

[package.json]
homepage = "https://example.com"
keywords = "gleam,functional"

[peer_dependencies]
react = ">=18"
```

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
