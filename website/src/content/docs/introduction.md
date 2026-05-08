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
- optional true-myth wrapper modules for top-level `Result` and `Option` types

## TypeScript support

talc uses Gleam's own `.d.mts` declaration files as the source of truth for TypeScript types. Because the Gleam compiler produces the JavaScript and declarations together, the declarations stay aligned with the compiled output.

Multi-module packages receive sub-path exports in `package.json` for each public module.

## true-myth wrappers

When `use_true_myth = true` (the default), talc generates thin wrapper modules for public modules whose functions use top-level `Result` or `Option` values. These wrappers convert to and from [true-myth](https://true-myth.js.org/) `Result` and `Maybe` types for a more ergonomic TypeScript API.

Only modules that use `Result` or `Option` get wrappers. talc adds `true-myth` as a peer dependency only when at least one wrapper is generated.
