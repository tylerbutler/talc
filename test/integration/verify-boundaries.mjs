#!/usr/bin/env node
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import {
  chmod, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const erlangBuild = path.join(root, "build/dev/erlang");
const beamFlags = (await readdir(erlangBuild)).flatMap(name => [
  "-pa", path.join(erlangBuild, name, "ebin"),
]);
const workParent = path.join(root, "test_work");
await mkdir(workParent, { recursive: true });
const work = await mkdtemp(path.join(workParent, "boundaries-"));
const build = path.join(work, "build/dev/javascript");
const output = path.join(work, "npm_dist");
const mockBin = path.join(work, "bin");
const environment = { ...process.env, PATH: mockBin + path.delimiter + process.env.PATH };
const metadata = '{"name":"boundary_fixture","version":"1.0.0","type":"module"}';

function command(executable, args, cwd = work, env = process.env) {
  const result = spawnSync(executable, args, { cwd, env, encoding: "utf8" });
  assert.ifError(result.error);
  return { ...result, text: result.stdout + result.stderr };
}

function writeOutput(destination = "npm_dist") {
  assert.match(destination, /^[a-zA-Z0-9_/.]+$/);
  return command("erl", [
    "-noshell", ...beamFlags, "-eval",
    `case talc@output:write(<<"${destination}">>, <<"boundary_fixture">>,
      <<${JSON.stringify(metadata)}>>, {some, [<<"boundary_fixture">>]}) of
      {ok, _} -> erlang:halt(0);
      {error, Error} ->
        io:format("~ts~n", [talc@output:error_to_string(Error)]),
        erlang:halt(1) end.`,
  ]);
}

function cli(args) {
  return command("erl", [
    "-noshell", ...beamFlags,
    "-eval", "talc:main(), erlang:halt(0).", "-extra", ...args,
  ], work, environment);
}

async function mockCompiler(body) {
  const executable = path.join(mockBin, "gleam");
  await writeFile(executable, "#!/bin/sh\n" + body + "\n");
  await chmod(executable, 0o755);
}

async function snapshot(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await snapshot(filename));
    else files.push([filename, await readFile(filename)]);
  }
  return files.sort(([left], [right]) => left.localeCompare(right));
}

function pack(directory) {
  const result = command("npm", [
    "pack", "--json", "--ignore-scripts", "--pack-destination", work,
    "--cache", path.join(work, "npm-cache"),
  ], directory);
  assert.equal(result.status, 0, result.text);
  return JSON.parse(result.stdout)[0].files.map(file => file.path);
}

try {
  await mkdir(path.join(build, "boundary_fixture"), { recursive: true });
  await mkdir(path.join(build, "removed_dependency"), { recursive: true });
  await mkdir(mockBin);
  for (const name of ["boundary_fixture", "gleam"]) {
    for (const ext of [".mjs", ".d.mts"]) {
      await writeFile(path.join(build, "boundary_fixture", name + ext), "// current\n");
    }
  }
  for (const name of ["prelude.mjs", "prelude.d.mts"]) {
    await writeFile(path.join(build, name), "// prelude\n");
  }
  const removedModule = path.join(build, "boundary_fixture", "private.mjs");
  const removedDependency = path.join(build, "removed_dependency");
  await writeFile(removedModule, "// removed module\n");
  await writeFile(path.join(removedDependency, "runtime.mjs"), "// removed dependency\n");
  await writeFile(path.join(work, "gleam.toml"), 'name = "boundary_fixture"\nversion = "1.0.0"\n');

  // Missing optional assets are valid; present files must retain arbitrary bytes.
  let result = writeOutput();
  assert.equal(result.status, 0, result.text);
  for (const asset of ["README.md", "LICENSE", "LICENSE-MIT", "LICENSE-APACHE"]) {
    await writeFile(path.join(work, asset), Buffer.from([0x61, 0x0d, 0x0a, 0xff, 0x00]));
  }
  result = writeOutput();
  assert.equal(result.status, 0, result.text);
  for (const asset of ["README.md", "LICENSE", "LICENSE-MIT", "LICENSE-APACHE"]) {
    assert.deepEqual(await readFile(path.join(output, asset)), await readFile(path.join(work, asset)));
  }
  const firstFiles = pack(output);
  assert.ok(firstFiles.includes("dist/private.mjs"));
  assert.ok(firstFiles.includes("removed_dependency/runtime.mjs"));
  await writeFile(path.join(output, "notes.txt"), "keep this user file");
  const original = await snapshot(output);
  result = writeOutput();
  assert.equal(result.status, 0, result.text);

  await rm(removedModule);
  await rm(removedDependency, { recursive: true });
  await writeFile(path.join(build, "boundary_fixture", "boundary_fixture.mjs"), "// changed\n");
  result = writeOutput();
  assert.equal(result.status, 1, result.text);
  assert.match(result.text, /Obsolete package artifact.*(?:private|removed_dependency)/);
  assert.match(result.text, /fresh output directory/);
  assert.deepEqual(await snapshot(output), original, "stale refusal must precede all writes");

  // Prove pack/publish stop before reaching npm when generation refuses output.
  await mockCompiler("printf '%s\\n' \"$TALC_TEST_INTERFACE\" > \"$4\"");
  environment.TALC_TEST_INTERFACE = JSON.stringify({
    name: "boundary_fixture", version: "1.0.0", "gleam-version-constraint": ">= 1.16.0",
    modules: { boundary_fixture: { documentation: [], "type-aliases": {}, types: {}, constants: {}, functions: {} } },
  });
  await writeFile(path.join(mockBin, "npm"), "#!/bin/sh\nprintf called > npm-was-called\nexit 1\n");
  await chmod(path.join(mockBin, "npm"), 0o755);
  for (const args of [["pack"], ["publish", "--dry-run=true"]]) {
    result = cli(args);
    assert.equal(result.status, 1, result.text);
    assert.match(result.text, /Obsolete package artifact/);
  }
  await assert.rejects(readFile(path.join(work, "npm-was-called")), { code: "ENOENT" });

  result = writeOutput("fresh_output");
  assert.equal(result.status, 0, result.text);
  const freshFiles = pack(path.join(work, "fresh_output"));
  assert.equal(freshFiles.includes("dist/private.mjs"), false);
  assert.equal(freshFiles.includes("removed_dependency/runtime.mjs"), false);

  // Optional assets that disappear are stale too, and directories are errors.
  await rm(path.join(work, "LICENSE-APACHE"));
  result = writeOutput("fresh_output");
  assert.equal(result.status, 1, result.text);
  assert.match(result.text, /Obsolete package artifact.*LICENSE-APACHE/);
  await mkdir(path.join(work, "LICENSE-APACHE"));
  result = writeOutput("asset_error");
  assert.equal(result.status, 1, result.text);
  assert.match(result.text, /Failed to inspect LICENSE-APACHE/);
  await rm(path.join(work, "LICENSE-APACHE"), { recursive: true });

  // A selected destination that is not a file is reported before mutation.
  await mkdir(path.join(work, "asset_destination/LICENSE"), { recursive: true });
  result = writeOutput("asset_destination");
  assert.equal(result.status, 1, result.text);
  assert.match(result.text, /Failed to inspect.*LICENSE/);

  // Link rejection is based on lstat, not on whether the target exists.
  await symlink(output, path.join(work, "linked_output"));
  result = writeOutput("linked_output");
  assert.equal(result.status, 1, result.text);
  assert.match(result.text, /Unsafe filesystem path/);
  assert.deepEqual(await snapshot(output), original);

  // check remains a metadata report even with no JavaScript build.
  await rm(path.join(work, "build"), { recursive: true });
  for (const [body, expected] of [
    ["printf 'compiler diagnostic' >&2; exit 37", /exit code 37:\s*compiler diagnostic/],
    ["exit 0", /Failed to read package interface output.*[Nn]o such file/],
    ["printf '{invalid' > \"$4\"", /Failed to decode package interface JSON/],
    ["printf '{}' > \"$4\"", /Failed to decode package interface JSON/],
  ]) {
    await mockCompiler(body);
    result = cli(["check"]);
    assert.equal(result.status, 0, result.text);
    assert.match(result.text, /Package: boundary_fixture/);
    assert.match(result.text, /could not be validated/);
    assert.match(result.text, expected);
    assert.equal((await readdir(work)).some(name => name.startsWith(".talc_pkg_iface_")), false);
  }
  await writeFile(path.join(work, "talc.ccl"), "package =\n  scope =\n    invalid = object\n");
  result = cli(["check"]);
  assert.equal(result.status, 1, result.text);
  assert.match(result.text, /package.scope must be a string/);
  await rm(path.join(work, "talc.ccl"));
  await writeFile(path.join(work, "gleam.toml"),
    'name = "boundary_fixture"\nversion = "1.0.0"\nlicences = ["MIT", "Apache-2.0"]\n');
  result = cli(["check"]);
  assert.match(result.text, /require an explicit package.json license override/);
  assert.deepEqual(await snapshot(output), original, "check must not touch package output");
} finally {
  await rm(work, { recursive: true, force: true });
}

console.log("Output containment, two-generation tarballs, asset errors, and metadata-only check passed");
