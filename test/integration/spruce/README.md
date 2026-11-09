# Spruce acceptance proof

Run this opt-in integration target from the Talc checkout:

```sh
just test-integration-spruce
```

It needs Gleam 1.16 or later, Erlang/OTP, Node.js, npm, git, tar, and network
access to GitHub, Hex, and the npm registry. It is not part of `just ci` or
default CI. It runs `pack`, never `publish`. npm lifecycle scripts are disabled.

## What the proof checks

The runner fetches Spruce revision
`5f799aeffb85656424757f48eed7b1410c07ad1f` into a new temporary directory.
It preserves the committed `manifest.toml` and builds JavaScript with native
declarations enabled by Spruce's own `gleam.toml`. The manifest's SHA256 is
`56808a85de7d12abef11a67a4def097f1d020400da2687d006237e7a65544213`.
TypeScript is pinned to `5.9.3`.

The runner prints the selected Talc revision, working changes, host, tool
versions, exact commands, lock digest, and each stage's result. It checks:

- Root, public submodule, and `spruce/gleam` imports by installed package name;
  dependency and implementation paths are not public exports.
- Exact no-color success, styled box, and table output with native contexts,
  colors, styles, lists, and custom-type helpers.
- Markdown rendering through mork and **colored** JavaScript highlighting
  through smalto. A no-color highlighting check alone would skip tokenization.
- Strict NodeNext declaration resolution, including expected errors for wrong
  primitive, context, collection, color, Result, and hidden-import types.
- Installed native JavaScript, FFI, and declaration hashes against every
  corresponding compiler artifact; named licence texts match source bytes.
- An unchanged rebuild and repeat pack produce identical unpacked file names
  and bytes. The first tarball is moved out of the output directory before
  repacking, so the second package cannot accidentally contain it.
- A separate, harness-owned two-generation fixture removes a private module
  and its Gleam dependency. Stale output must be rejected before **any** output
  file changes, including an unrelated user file. A fresh output directory must
  produce a tarball without either obsolete path.

The tarball is copied to a separate consumer directory. The Spruce source,
build, and package-output directory is then deleted **before** npm installation,
runtime execution, or type checking. The consumer uses only its installed
package and TypeScript; it does not import from Talc, Spruce's source checkout,
or a build directory. Generated JavaScript and declarations are not edited.
Harness-owned temporary directories are removed on success or failure.

### Terminal detection

Detection runs separately from deterministic rendering. Each Node child has
piped stdout/stderr and controlled environment variables. With `TERM=dumb`,
the unforced case and `NO_COLOR=1` must detect no color.
`FORCE_COLOR=3` must detect true color. Each case checks both `detect()` and
explicit stdout/stderr detection, and prints its environment and result.
This tests installed tty runtime artifacts; it does not claim an interactive
TTY or a particular real terminal was tested.

### Licence test configuration

Before adding configuration, the runner checks that multiple Gleam licences
without an explicit metadata override are rejected before writes. It then
adds this **test-only** `talc.ccl` to the disposable source copy:

```ccl
package.json =
  license = SEE LICENSE IN LICENSE-MIT
```

This npm-supported reference exercises explicit metadata override preservation.
It is **not** an authoritative conclusion about the relation between Spruce's
MIT and Apache-2.0 terms. Both `LICENSE-MIT` and `LICENSE-APACHE` must remain
byte-identical in the installed tarball. No Spruce source, committed upstream
configuration, or generated output is changed, and no package is published.

### Native consumer friction

The compiler emits `new$()` for Gleam functions named `new`. Collections stay
native: table rows need `List.fromArray` at both list levels, imported through
`spruce/gleam`. Custom-type values use compiler helpers such as
`Color$Green()`, not strings or invented objects. `Result$Ok$0` can return
`undefined` in the declaration, so the TypeScript consumer explicitly guards
that result before passing a resolved language onward.

Spruce declares no internal modules at the pinned revision. For example,
`spruce/detail` is public and must not be hidden merely because of its name.
The runner checks hidden dependency/deep import paths and the private opaque
context constructor. The separate stale-output fixture declares a private
module and checks that it has no automatic export.

These are native API usage details, not reasons to add wrappers or expose
dependency packages. This target makes no browser, Deno, Bun, CommonJS, bundling,
or automatic npm dependency-inference claims.

## Selecting a packaging revision

The default target builds Talc in the checkout containing the proof. To test a
separate remotely available code revision without stacking or cherry-picking,
create a disposable checkout and point the proof at it:

```sh
scratch="$(mktemp -d)"
git -C "$scratch" init --quiet
git -C "$scratch" fetch --depth=1 https://github.com/tylerbutler/talc.git CODE_SHA
git -C "$scratch" checkout --detach FETCH_HEAD
TALC_SPRUCE_TALC_DIR="$scratch" just test-integration-spruce
# Remove only this disposable checkout when finished.
```

Replace `CODE_SHA` with the full verified commit ID. The runner reports that
checkout's revision and working changes; it does not change this proof
branch's ancestry. Never point it at a primary Spruce or Talc checkout.

## Recorded results

### Baseline, not full acceptance

Talc `9d5bf8a8fbbda4ed30f292290aa7c039a4536404` with the pinned Spruce revision:

| Check | Result |
| --- | --- |
| JavaScript build and real Talc `pack` | Pass |
| Unchanged rebuild/repack, unpacked names and bytes | Pass |
| Installed compiler artifacts | Pass: 410 SHA256 matches |
| Native rendering, collections, public/hidden paths | Pass |
| Markdown and colored syntax-highlighting runtime | Pass |
| Strict NodeNext positive/negative types | Pass |
| Separate controlled non-TTY detection | Pass |
| Multiple licences without metadata override | **Fail:** first licence silently selected (#25) |
| Obsolete module/dependency output | **Fail:** stale files silently retained (#24) |
| Named licence texts | **Fail:** files absent from installed tarball (#25) |

These results came from `just test-integration-spruce`, which exits nonzero
and reports all three failed stages while still checking independent consumer
stages. Baseline is not full acceptance and does not close #23.

Recorded tools: Gleam `1.19.2`, Node.js `24.21.0`, npm `11.19.0`,
Erlang/OTP `27` with ERTS `15.2.7.8`, git `2.56.0`, just `1.59.0`;
host Darwin `27.2.0`, arm64. These are the tools actually used, not a claim
that every configured or supported version was tested.
