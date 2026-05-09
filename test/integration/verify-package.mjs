#!/usr/bin/env node
// Integration verifier: imports from the talc-generated npm_dist and asserts
// that plain functions, true-myth-wrapped Results, and submodule exports work.

import { strict as assert } from "node:assert";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.resolve(
  __dirname,
  "../fixtures/basic_gleam_package/npm_dist/dist",
);

// 1. Root module: plain function (no wrapping)
const rootModule = await import(path.join(distDir, "basic_gleam_package.mjs"));
assert.strictEqual(
  rootModule.greet("World"),
  "Hello, World!",
  "greet() returns expected string",
);

// 2. True-myth wrapper: Result-returning function
const wrapper = await import(
  path.join(distDir, "_wrapper/basic_gleam_package.mjs")
);

const okResult = wrapper.parse_positive("42");
assert.strictEqual(okResult.isOk, true, 'parse_positive("42").isOk');
assert.strictEqual(okResult.value, 42, 'parse_positive("42").value === 42');

const errResult = wrapper.parse_positive("abc");
assert.strictEqual(errResult.isOk, false, 'parse_positive("abc") should be Err');

// 3. Submodule export
const mathModule = await import(
  path.join(distDir, "basic_gleam_package/math.mjs")
);
assert.strictEqual(mathModule.add(2, 3), 5, "add(2, 3) === 5");

// 4. Wrapper declarations preserve external TypeScript aliases
const wrapperDeclaration = await readFile(
  path.join(distDir, "_wrapper/basic_gleam_package.d.ts"),
  "utf8",
);
assert.match(
  wrapperDeclaration,
  /import type \{ Thing as Thing\$ \} from "\.\.\/thing\.d\.mts";/,
  "wrapper declaration imports external Thing type with rebased path",
);
assert.match(
  wrapperDeclaration,
  /Result<Thing\$<number>, string>/,
  "wrapper declaration preserves external Thing alias inside Result",
);

console.log("✓ All integration checks passed");
