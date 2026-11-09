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

The default root entrypoint requires a public module whose name matches
`name` in `gleam.toml`. For `name = "mylib"`, provide `src/mylib.gleam` and
do not mark it as internal.

If you use a different root module, override all four `package.json`
entrypoint fields in `talc.ccl`: `exports`, `main`, `module`, and `types`.
An `exports` override alone does not remove the root-module requirement.

## 3. Build your project for JavaScript

```sh
gleam build --target javascript
```

## 4. Validate talc configuration

Run `check` before writing files:

```sh
gleam run -m talc -- check
```

`check` reports configuration issues. It is not a full runtime or TypeScript
check; inspect and exercise the generated package before publishing.

## 5. Generate the npm package

```sh
gleam run -m talc -- generate
```

By default, talc writes the package to `npm_dist/`.

## 6. Inspect the output

The generated package includes:

```text
npm_dist/
├── package.json
├── README.md                # Copied from project root, if present
├── LICENSE                  # Copied from project root, if present
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

Node.js and npm must be available on `PATH`.

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

`--access` accepts only `public` or `restricted`. `--tag` must be non-empty
and contain only ASCII letters, numbers, `_`, `-`, or `.`. These are talc's
checks; npm can apply additional restrictions.

Use a custom output directory for any of these commands:

```sh
gleam run -m talc -- generate --output-dir my_output
gleam run -m talc -- pack --output-dir my_output
gleam run -m talc -- publish --output-dir my_output
```

`--output-dir` overrides `package.output_dir` in `talc.ccl`; the default is
`npm_dist`. Use a non-empty path relative to the project root, with no `..`
components. For example, `packages/npm` is allowed, but `../npm` and
`packages/../npm` are rejected. These checks are lexical; they do not
guarantee containment through symlinks.
