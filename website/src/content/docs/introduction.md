---
title: What is talc?
description: An introduction to talc and Gleam-to-npm packaging.
---

talc is an npm packaging tool for Gleam libraries. It reads a compiled Gleam JavaScript build and produces a publish-ready npm package directory.

## Why talc?

Gleam can compile libraries to JavaScript, but npm packages need more than compiled modules. talc bridges that gap by preparing the files and metadata TypeScript and npm consumers expect:

- a generated `package.json` derived from `gleam.toml`
- compiled `.mjs` files copied from `build/dev/javascript`
- Gleam compiler-generated `.d.mts` declarations copied from the same build
- dependency JavaScript artifacts placed next to `dist/` for runtime imports
- private modules and local JavaScript FFI artifacts needed by public functions

## TypeScript support

talc uses Gleam's own `.d.mts` declaration files as the source of truth for TypeScript types. Because the Gleam compiler produces the JavaScript and declarations together, the declarations stay aligned with the compiled output.

Multi-module packages receive sub-path exports in `package.json` for each public module.

## Native interop

Consumers use native Gleam values. Import the compiler's Result, List, and
BitArray helpers from `<package>/gleam`. Import custom-type constructors and
accessors from the public module that defines the type.

Follow [Gleam's externals documentation](https://gleam.run/documentation/externals/)
for the supported JavaScript API. talc copies declarations without parsing or
rewriting types. It preserves private modules and local FFI files, but only
exports public modules and the `./gleam` support module.

Authors must supply external declarations and configure npm dependencies
used by bare imports. talc does not check external implementations.

## Migrating from true-myth

Remove `package.use_true_myth` from `talc.ccl` and update consumers to native
Gleam values. Use fresh output or remove the legacy `dist/_wrapper` directory
before generating. talc rejects the removed option and legacy wrapper output
with migration instructions.
