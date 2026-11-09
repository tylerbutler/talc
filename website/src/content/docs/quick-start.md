---
title: Quick Start
description: Generate your first npm package with talc.
---

This guide walks through generating an npm package from a Gleam library.

Use Gleam 1.16 or later so the build includes external type declarations.

## 1. Add talc to your project

```sh
gleam add --dev talc
```

## 2. Enable TypeScript declarations

Add this to your `gleam.toml`:

```toml
[javascript]
typescript_declarations = true
```

## 3. Build your project for JavaScript

```sh
gleam build --target javascript
```

## 4. Validate talc configuration

Run `check` before writing files:

```sh
gleam run -m talc -- check
```

## 5. Generate the npm package

```sh
gleam run -m talc -- generate
```

By default, talc writes the package to `npm_dist/`.

Use a non-root relative output path with forward slashes. talc rejects unsafe
path forms and symlinks in output paths and output trees, including dangling
links. It also rejects multiply linked files.

Repeat generation works when existing artifacts belong to the current build.
If you remove a module, dependency, or selected asset, use a fresh output directory
when talc reports obsolete files. talc checks this before writes and does not
delete user files. Extra JavaScript or declaration files can trigger the same
refusal.

The optional package assets are `README.md`, `LICENSE`, `LICENSE-MIT`, and
`LICENSE-APACHE`; talc preserves their bytes and reports copy errors. Multiple
`gleam.toml` licences require an explicit `package.json.license` override in
`talc.ccl` with the project's intended SPDX expression or npm license reference.

## 6. Inspect the output

The generated package includes:

```text
npm_dist/
├── package.json
├── README.md
├── LICENSE
├── prelude.mjs
├── prelude.d.mts
├── gleam_stdlib/
└── dist/
    ├── gleam.mjs
    ├── gleam.d.mts
    ├── mylib.mjs
    ├── mylib.d.mts
    └── ...                  # Private modules and local FFI artifacts
```

Import public modules by package name. Use `<package>/gleam` for native
Result, List, and BitArray helpers. See
[Gleam's externals documentation](https://gleam.run/documentation/externals/)
for constructors and accessors.

## 7. Pack or publish

Create a tarball with `npm pack`:

```sh
gleam run -m talc -- pack
```

Publish to npm:

```sh
gleam run -m talc -- publish
```

Common publish options:

```sh
gleam run -m talc -- publish --dry-run=true
gleam run -m talc -- publish --tag=beta
gleam run -m talc -- publish --access=public
gleam run -m talc -- publish --provenance=true
```

Use a custom output directory when generating:

```sh
gleam run -m talc -- generate --output-dir my_output
```
