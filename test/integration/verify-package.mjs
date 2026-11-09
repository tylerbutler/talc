#!/usr/bin/env node
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { copyFile, mkdtemp, readFile, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
const fixture = path.resolve(directory, "../fixtures/basic_gleam_package");
const packageDir = path.join(fixture, "npm_dist");
const metadata = JSON.parse(await readFile(path.join(packageDir, "package.json")));

assert.equal(metadata.peerDependencies, undefined);
assert.equal(metadata.license, "SEE LICENSE IN LICENSE");
assert.equal(metadata.exports["."].import, "./dist/basic_gleam_package.mjs");
assert.equal(metadata.exports["."].types, "./dist/basic_gleam_package.d.mts");
assert.equal(
  metadata.exports["./math"].import,
  "./dist/basic_gleam_package/math.mjs",
);
assert.equal(metadata.exports["./gleam"].import, "./dist/gleam.mjs");
assert.equal(metadata.exports["./internal"], undefined);

function run(command, arguments_, cwd) {
  const result = spawnSync(command, arguments_, { cwd, encoding: "utf8" });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout;
}

const consumerDir = await mkdtemp(path.join(fixture, ".talc-consumer-"));
try {
  const packed = JSON.parse(run("npm", [
    "pack", "--json", "--ignore-scripts", "--pack-destination", consumerDir,
    "--cache", path.join(consumerDir, "npm-cache"),
  ], packageDir));
  assert.equal(packed.length, 1);
  assert.equal(packed[0].files.some(file => file.path.includes("_wrapper")), false);
  run("npm", [
    "install", "--prefix", consumerDir, "--no-save", "--no-audit", "--no-fund",
    "--ignore-scripts", "--package-lock=false",
    "--cache", path.join(consumerDir, "npm-cache"),
    path.join(consumerDir, packed[0].filename),
  ], consumerDir);
  const installedDir = path.join(consumerDir, "node_modules/basic_gleam_package");

  for (const asset of ["LICENSE", "LICENSE-MIT", "LICENSE-APACHE"]) {
    assert.ok(packed[0].files.some(file => file.path === asset), `${asset} is packed`);
    assert.deepEqual(
      await readFile(path.join(installedDir, asset)),
      await readFile(path.join(fixture, asset)),
      `${asset} stays unchanged in the tarball`,
    );
  }

  const artifacts = [
    "basic_gleam_package.mjs",
    "basic_gleam_package.d.mts",
    "thing.d.mts",
    "identity.js",
    "basic_gleam_package/internal.mjs",
    "basic_gleam_package/greeting.mjs",
  ];
  for (const artifact of artifacts) {
    assert.deepEqual(
      await readFile(path.join(installedDir, "dist", artifact)),
      await readFile(path.join(
        fixture, "build/dev/javascript/basic_gleam_package", artifact,
      )),
      `${artifact} stays unchanged`,
    );
  }

  run(process.execPath, ["--input-type=module", "--eval", `
    import { strict as assert } from "node:assert";
    import * as library from "basic_gleam_package";
    import { add } from "basic_gleam_package/math";
    import {
      Result$Ok, Result$Error, Result$isOk, Result$isError,
      Result$Ok$0, Result$Error$0,
    } from "basic_gleam_package/gleam";
    import {
      Option$isSome, Option$isNone, Option$Some$0,
    } from "./node_modules/basic_gleam_package/gleam_stdlib/gleam/option.mjs";

    assert.equal(library.greet("World"), "Hello, World!");
    assert.equal(add(2, 3), 5);
    const ok = library.parse_positive("42");
    assert.equal(Result$isOk(ok), true);
    assert.equal(Result$Ok$0(ok), 42);
    const error = library.parse_positive("abc");
    assert.equal(Result$isError(error), true);
    assert.equal(Result$Error$0(error), "not a number");
    assert.equal(Result$isError(library.parse_positive("0")), true);
    const thing = { value: 7 };
    assert.equal(Result$Ok$0(library.keep_thing(thing)), thing);
    const person = library.Person$Person("Ada");
    assert.equal(library.Person$isPerson(person), true);
    assert.equal(library.Person$Person$name(person), "Ada");
    assert.equal(library.person_name(person), "Ada");
    const some = library.result_to_option(Result$Ok(42));
    assert.equal(Option$isSome(some), true);
    assert.equal(Option$Some$0(some), 42);
    assert.equal(
      Option$isNone(library.result_to_option(Result$Error("error"))),
      true,
    );
    assert.equal(library.external_greeting("World"), "Hi, World!");
    assert.equal(library.identity(42), 42);
  `], consumerDir);

  const consumer = path.join(consumerDir, "consumer.mts");
  await copyFile(path.join(directory, "consumer.mts"), consumer);
  run(process.execPath, [
    path.join(fixture, "node_modules/typescript/bin/tsc"),
    "--noEmit", "--strict", "--module", "NodeNext", "--target", "ES2022",
    consumer,
  ], consumerDir);
} finally {
  await rm(consumerDir, { recursive: true, force: true });
}

console.log("Native runtime, package exports, FFI, and TypeScript checks passed");
