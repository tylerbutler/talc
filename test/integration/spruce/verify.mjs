#!/usr/bin/env node
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFile, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
const talc = path.resolve(process.env.TALC_SPRUCE_TALC_DIR ?? path.join(directory, "../../.."));
const spruceRevision = "5f799aeffb85656424757f48eed7b1410c07ad1f";
const typescriptVersion = "5.9.3";
const temporary = await mkdtemp(path.join(os.tmpdir(), "talc-spruce-"));
const source = path.join(temporary, "spruce");
const consumer = path.join(temporary, "consumer");
const failures = [];
const environment = {
  ...process.env,
  npm_config_cache: path.join(temporary, "npm-cache"),
  npm_config_ignore_scripts: "true",
};

function command(executable, args, cwd, { env = environment, status = 0 } = {}) {
  console.log(`$ (${cwd}) ${[executable, ...args].map(JSON.stringify).join(" ")}`);
  const result = spawnSync(executable, args, {
    cwd, env, encoding: "utf8", maxBuffer: 16 * 1024 * 1024,
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null, `${executable} terminated by signal`);
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (status !== null) assert.equal(result.status, status, `${executable} failed`);
  return result;
}

async function stage(name, check) {
  try {
    await check();
    console.log(`PASS ${name}`);
  } catch (error) {
    failures.push(new Error(name, { cause: error }));
    console.error(`FAIL ${name}: ${error.stack}`);
  }
}

const hash = bytes => createHash("sha256").update(bytes).digest("hex");

async function filesBelow(root) {
  const files = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const name = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await filesBelow(name));
    else if (entry.isFile()) files.push(name);
    else assert.fail(`Unexpected non-file artifact: ${name}`);
  }
  return files.sort();
}

async function artifactHashes(root) {
  const artifacts = new Map();
  for (const file of await filesBelow(root)) {
    if (/\.(mjs|js|d\.mts|d\.ts)$/.test(file)) {
      artifacts.set(path.relative(root, file), hash(await readFile(file)));
    }
  }
  return artifacts;
}

async function fileHashes(root) {
  const hashes = new Map();
  for (const file of await filesBelow(root)) {
    hashes.set(path.relative(root, file), hash(await readFile(file)));
  }
  return hashes;
}

let beamArgs;
function runTalc(cwd, args, options) {
  return command("erl", [
    "-noshell", ...beamArgs,
    "-eval", "talc:main(), erlang:halt(0).", "-extra", ...args,
  ], cwd, options);
}

async function pack(cwd, output) {
  runTalc(cwd, ["pack", `--output-dir=${output}`]);
  const tarballs = (await readdir(path.join(cwd, output)))
    .filter(name => name.endsWith(".tgz"));
  assert.equal(tarballs.length, 1, "Talc pack creates exactly one tarball");
  return path.join(cwd, output, tarballs[0]);
}

async function staleOutputProof() {
  const fixture = path.join(temporary, "stale-fixture");
  await mkdir(path.join(fixture, "src/probe"), { recursive: true });
  const config = `name = "probe"
version = "1.0.0"
internal_modules = ["probe/private"]
[javascript]
typescript_declarations = true
`;
  await writeFile(path.join(fixture, "gleam.toml"),
    `${config}[dependencies]\ngleam_stdlib = "== 1.0.5"\n`);
  await writeFile(path.join(fixture, "src/probe.gleam"),
    'import probe/private\npub fn value() { private.value() }\n');
  await writeFile(path.join(fixture, "src/probe/private.gleam"),
    'import gleam/string\npub fn value() { string.length("old") }\n');
  command("gleam", ["build", "--target", "javascript"], fixture);
  await pack(fixture, "npm_dist");
  const output = path.join(fixture, "npm_dist");
  const previous = await artifactHashes(output);
  assert.equal(previous.has("dist/probe/private.mjs"), true);
  assert.equal(previous.has("gleam_stdlib/gleam/string.mjs"), true);
  const firstMetadata = JSON.parse(await readFile(path.join(output, "package.json")));
  assert.equal(firstMetadata.exports["./private"], undefined);
  const userFile = path.join(output, "user-note.txt");
  await writeFile(userFile, "preserve this user file\n");
  const allPrevious = await fileHashes(output);
  await writeFile(path.join(fixture, "src/probe.gleam"), "pub fn value() { 1 }\n");
  await rm(path.join(fixture, "src/probe/private.gleam"));
  await writeFile(path.join(fixture, "gleam.toml"), config);
  await rm(path.join(fixture, "build"), { recursive: true });
  command("gleam", ["build", "--target", "javascript"], fixture);
  const repeated = runTalc(fixture, ["pack"], { status: null });
  assert.notEqual(repeated.status, 0, "obsolete output must be rejected");
  assert.match(repeated.stdout + repeated.stderr, /stale|obsolete/i);
  assert.deepEqual(await artifactHashes(output), previous, "rejection does not alter artifacts");
  assert.deepEqual(await fileHashes(output), allPrevious, "rejection does not alter any output file");
  assert.equal(await readFile(userFile, "utf8"), "preserve this user file\n");
  const freshTarball = await pack(fixture, "npm_fresh");
  const listing = command("tar", ["-tzf", freshTarball], fixture).stdout;
  assert.doesNotMatch(listing, /probe\/private|gleam_stdlib/);
}

try {
  console.log(`Spruce revision: ${spruceRevision}`);
  console.log(`Talc revision: ${command("git", ["rev-parse", "HEAD"], talc).stdout.trim()}`);
  console.log(`Talc working changes:\n${command("git", ["status", "--short"], talc).stdout}`);
  console.log(`Host: ${process.platform} ${process.arch}; ${os.release()}`);
  for (const executable of ["gleam", "node", "npm", "git"]) {
    command(executable, ["--version"], talc);
  }
  command("erl", ["-noshell", "-eval",
    'io:format("OTP ~s; ERTS ~s~n", [erlang:system_info(otp_release), erlang:system_info(version)]), halt().',
  ], talc);
  command("gleam", ["build"], talc);
  beamArgs = [];
  for (const entry of await readdir(path.join(talc, "build/dev/erlang"), { withFileTypes: true })) {
    if (entry.isDirectory()) {
      beamArgs.push("-pa", path.join(talc, "build/dev/erlang", entry.name, "ebin"));
    }
  }

  await mkdir(source);
  await mkdir(consumer);
  command("git", ["init", "--quiet"], source);
  command("git", ["fetch", "--quiet", "--depth=1",
    "https://github.com/tylerbutler/spruce.git", spruceRevision,
  ], source);
  command("git", ["checkout", "--quiet", "--detach", "FETCH_HEAD"], source);
  assert.equal(command("git", ["rev-parse", "HEAD"], source).stdout.trim(), spruceRevision);
  const lock = await readFile(path.join(source, "manifest.toml"));
  console.log(`Spruce manifest.toml SHA256: ${hash(lock)}`);
  command("gleam", ["build", "--target", "javascript"], source);
  assert.deepEqual(await readFile(path.join(source, "manifest.toml")), lock);
  assert.equal(command("git", ["diff", "--exit-code"], source).stdout, "");
  await stage("multiple licences require an explicit metadata override", async () => {
    try {
      const missing = runTalc(source, ["generate", "--output-dir=npm_no_override"], {
        status: null,
      });
      assert.notEqual(missing.status, 0, "multiple licences must not silently select the first");
      assert.match(missing.stdout + missing.stderr, /licen[cs]e/i);
      assert.match(missing.stdout + missing.stderr, /override|package\.json/i);
      assert.equal((await readdir(source)).includes("npm_no_override"), false,
        "metadata rejection happens before output writes");
    } finally {
      await rm(path.join(source, "npm_no_override"), { recursive: true, force: true });
    }
  });
  await writeFile(path.join(source, "talc.ccl"),
    "package.json =\n  license = SEE LICENSE IN LICENSE-MIT\n");
  console.log("Fixture-only talc.ccl: license = SEE LICENSE IN LICENSE-MIT (no inferred OR/AND)");

  const build = path.join(source, "build/dev/javascript");
  const expected = new Map();
  for (const [file, digest] of await artifactHashes(build)) {
    const target = file.startsWith(`spruce${path.sep}`)
      ? path.join("dist", file.slice("spruce/".length)) : file;
    expected.set(target, digest);
  }
  assert.ok(expected.size > 100, "real transitive artifact set");
  const licences = new Map();
  for (const name of ["LICENSE-MIT", "LICENSE-APACHE"]) {
    licences.set(name, await readFile(path.join(source, name)));
  }
  const firstTarball = await pack(source, "npm_dist");
  const installedTarball = path.join(consumer, "spruce.tgz");
  await rename(firstTarball, installedTarball);

  await stage("unchanged rebuild/repack is byte-stable", async () => {
    command("gleam", ["build", "--target", "javascript"], source);
    assert.deepEqual(await readFile(path.join(source, "manifest.toml")), lock);
    const secondTarball = await pack(source, "npm_dist");
    const secondConsumer = path.join(temporary, "second-consumer");
    await mkdir(secondConsumer);
    command("tar", ["-xzf",
      secondTarball, "-C", secondConsumer,
    ], temporary);
    command("tar", ["-xzf", installedTarball, "-C", consumer], temporary);
    const firstFiles = await filesBelow(path.join(consumer, "package"));
    const secondFiles = await filesBelow(path.join(secondConsumer, "package"));
    assert.deepEqual(
      firstFiles.map(file => path.relative(path.join(consumer, "package"), file)),
      secondFiles.map(file => path.relative(path.join(secondConsumer, "package"), file)),
    );
    for (let index = 0; index < firstFiles.length; index++) {
      assert.deepEqual(await readFile(firstFiles[index]), await readFile(secondFiles[index]));
    }
    await rm(path.join(consumer, "package"), { recursive: true });
  });
  await stage("obsolete module/dependency rejection and fresh-output recovery", staleOutputProof);

  await rm(source, { recursive: true });
  console.log("Removed Spruce source, build, and packaging output before consumer checks");
  await writeFile(path.join(consumer, "package.json"),
    JSON.stringify({ private: true, type: "module" }));
  command("npm", ["install", "--no-audit", "--no-fund", "--ignore-scripts",
    "--package-lock=false", "--save-exact", "./spruce.tgz", `typescript@${typescriptVersion}`,
  ], consumer);
  const installed = path.join(consumer, "node_modules/spruce");
  await stage("compiler artifact fidelity", async () => {
    for (const [file, digest] of expected) {
      assert.equal(hash(await readFile(path.join(installed, file))), digest, file);
    }
    console.log(`Matched ${expected.size} native runtime/declaration artifact hashes`);
  });
  await stage("named licence bytes", async () => {
    for (const [file, bytes] of licences) {
      assert.deepEqual(await readFile(path.join(installed, file)), bytes, file);
    }
  });
  await stage("public export metadata", async () => {
    const metadata = JSON.parse(await readFile(path.join(installed, "package.json")));
    assert.equal(metadata.name, "spruce");
    assert.equal(metadata.license, "SEE LICENSE IN LICENSE-MIT");
    assert.equal(metadata.exports["."].import, "./dist/spruce.mjs");
    assert.equal(metadata.exports["."].types, "./dist/spruce.d.mts");
    assert.equal(metadata.exports["./gleam"].import, "./dist/gleam.mjs");
    assert.equal(metadata.dependencies, undefined);
    assert.equal(metadata.peerDependencies, undefined);
    for (const [name, conditions] of Object.entries(metadata.exports)) {
      assert.deepEqual(Object.keys(conditions), ["types", "import"], name);
      assert.match(conditions.import, /^\.\/dist\//);
    }
  });
  for (const file of ["runtime.mjs", "detect.mjs", "consumer.mts"]) {
    await copyFile(path.join(directory, file), path.join(consumer, file));
  }
  await stage("installed runtime consumer", async () => {
    command(process.execPath, ["runtime.mjs"], consumer);
  });
  await stage("strict NodeNext positive and negative types", async () => {
    command(process.execPath, ["node_modules/typescript/bin/tsc", "--version"], consumer);
    command(process.execPath, [
      "node_modules/typescript/bin/tsc", "--noEmit", "--strict",
      "--module", "NodeNext", "--moduleResolution", "NodeNext", "--target", "ES2022",
      "consumer.mts",
    ], consumer);
  });
  await stage("controlled non-TTY terminal detection", async () => {
    const clean = { ...environment, TERM: "dumb" };
    for (const key of ["NO_COLOR", "FORCE_COLOR", "COLORTERM", "CI",
      "COLORFGBG", "TERM_PROGRAM"]) delete clean[key];
    for (const [expected, overrides] of [
      ["nocolor", {}],
      ["nocolor", { NO_COLOR: "1" }],
      ["truecolor", { FORCE_COLOR: "3" }],
    ]) {
      command(process.execPath, ["detect.mjs", expected], consumer, {
        env: { ...clean, ...overrides },
      });
    }
  });
  if (failures.length) throw new AggregateError(failures, `${failures.length} Spruce proof stages failed`);
  console.log("PASS Spruce MVP acceptance (no npm publication)");
} finally {
  await rm(temporary, { recursive: true, force: true });
}
