# talc

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
├── package.json           # Generated from gleam.toml
├── README.md              # Copied from project root (if present)
├── LICENSE                # Copied from project root (if present)
├── prelude.mjs            # Gleam prelude runtime
├── prelude.d.mts          # Gleam prelude type declarations
└── dist/
    ├── gleam.mjs          # Gleam runtime support
    ├── gleam.d.mts        # Gleam runtime type declarations
    ├── mylib.mjs          # Compiled JS (Gleam native)
    ├── mylib.d.mts        # TypeScript declarations (Gleam native)
    ├── _wrapper/          # true-myth wrapper modules (if enabled)
    │   ├── mylib.mjs      # Wrapper JS (Result/Option conversion)
    │   └── mylib.d.ts     # Wrapper type declarations
    └── _types/            # External type declarations (if any)
        └── gleam_json/
            └── gleam/
                ├── json.d.ts   # User-provided type declarations
                └── json.mjs    # Empty stub for module resolution
```

### TypeScript Support

talc uses Gleam's native `.d.mts` type declarations (generated via
`typescript_declarations = true` in `gleam.toml`) as the source of truth. When
`use_true_myth = true` (the default), talc generates thin wrapper modules that
convert top-level `Result` and `Option` types to `true-myth` `Result` and `Maybe`
types.

### External Type Declarations

When wrapper `.d.ts` files reference types from external Gleam packages (e.g.,
`Json` from `gleam_json`), talc needs to know what TypeScript type to use. By
default, unresolvable types are emitted as `unknown`.

To provide proper types, create a `talc-types/` directory mirroring Gleam's
`{package}/{module}` structure with standard `.d.ts` files:

```
talc-types/
  gleam_json/
    gleam/
      json.d.ts
  gleam_erlang/
    gleam/
      erlang/
        process.d.ts
  birl/
    birl.d.ts
```

Each file exports TypeScript type declarations:

```typescript
// talc-types/gleam_json/gleam/json.d.ts
export type Json = string;
```

```typescript
// talc-types/gleam_erlang/gleam/erlang/process.d.ts
export type Subject<T> = { readonly phantom: T };
```

talc discovers these files at build time and generates proper `import type`
statements in the wrapper `.d.ts` files. The declaration files are copied into
the npm output (`dist/_types/`) so the package is self-contained.

Types without matching declaration files emit `unknown` with a warning.

### Configuration

`talc` reads metadata from your `gleam.toml` automatically. To customize the npm package,
create a `talc.ccl` in your project root:

```ccl
package =
  scope = @myorg
  output_dir = npm_dist
  registry = https://registry.npmjs.org

/= Directory containing .d.ts type declarations for external types.
/= Default: talc-types
type_declarations_dir = talc-types

/= Set to false to disable true-myth wrapper generation.
/= Default: true
use_true_myth = true

package.json =
  homepage = https://example.com
  private = true
  keywords =
    = gleam
    = functional

peer_dependencies =
  react = >=18
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
