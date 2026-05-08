---
title: Quick Start
description: Generate your first npm package with talc.
---

This guide walks through generating an npm package from a Gleam library.

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
    └── _wrapper/
        ├── mylib.mjs
        └── mylib.d.ts
```

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
