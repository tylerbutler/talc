---
title: Installation
description: How to install talc in your Gleam project.
---

Add talc as a development dependency:

```sh
gleam add --dev talc
```

## Enable TypeScript declarations

talc expects your Gleam JavaScript build to include compiler-generated TypeScript declarations. Enable them in `gleam.toml`:

```toml
[javascript]
typescript_declarations = true
```

## Requirements

- **Gleam** >= 1.16.0 so the JavaScript build includes external type declarations
- **Erlang/OTP** to run talc on the BEAM
- **Node.js and npm** available on `PATH` for `pack` and `publish`
- **JavaScript build output** from `gleam build --target javascript`

## Optional configuration

talc reads package metadata from `gleam.toml` automatically. To customize the npm package, create a `talc.ccl` file in your project root:

```text
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

`package.output_dir` defaults to `npm_dist`. Use a non-empty path relative to
the project root, with no `..` components. These checks are lexical; they do
not guarantee containment through symlinks. `generate`, `pack`, and `publish`
also accept `--output-dir` to override this setting. See the
[Quick Start](/quick-start/#7-pack-or-publish) for examples.
