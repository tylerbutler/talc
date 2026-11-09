/// Tests for output directory validation and required artifact checking.
import gleam/list
import gleam/option.{None, Some}
import simplifile
import startest/expect
import talc/output.{
  MissingArtifact, UnsafeOutputDir, error_to_string, validate_output_dir,
}

// ─── validate_output_dir ─────────────────────────────────────────────────────

pub fn validate_output_dir_accepts_relative_test() {
  validate_output_dir("npm_dist")
  |> expect.to_equal(Ok(Nil))
}

pub fn validate_output_dir_accepts_nested_relative_test() {
  validate_output_dir("foo/bar")
  |> expect.to_equal(Ok(Nil))
}

pub fn validate_output_dir_rejects_absolute_test() {
  validate_output_dir("/tmp/out")
  |> expect.to_be_error()
  Nil
}

pub fn validate_output_dir_rejects_dotdot_standalone_test() {
  validate_output_dir("..")
  |> expect.to_be_error()
  Nil
}

pub fn validate_output_dir_rejects_dotdot_prefix_test() {
  validate_output_dir("../outside")
  |> expect.to_be_error()
  Nil
}

pub fn validate_output_dir_rejects_inline_traversal_test() {
  validate_output_dir("foo/../bar")
  |> expect.to_be_error()
  Nil
}

pub fn validate_output_dir_rejects_trailing_parent_test() {
  validate_output_dir("foo/..")
  |> expect.to_be_error()
  Nil
}

pub fn validate_output_dir_rejects_nested_trailing_parent_test() {
  validate_output_dir("a/b/..")
  |> expect.to_be_error()
  Nil
}

pub fn validate_output_dir_rejects_empty_test() {
  validate_output_dir("")
  |> expect.to_equal(Error(UnsafeOutputDir("")))
}

// ─── error_to_string ─────────────────────────────────────────────────────────

pub fn error_to_string_unsafe_output_dir_test() {
  error_to_string(UnsafeOutputDir("/evil"))
  |> expect.string_to_contain("Unsafe")
}

pub fn error_to_string_missing_artifact_test() {
  error_to_string(MissingArtifact(
    "build/dev/javascript/pkg/mod.mjs",
    "out/dist/mod.mjs",
  ))
  |> expect.string_to_contain("build/dev/javascript/pkg/mod.mjs")
}

// ─── write: unsafe dir rejection (no filesystem needed) ─────────────────────

pub fn write_rejects_absolute_output_dir_test() {
  output.write("/evil/path", "mypkg", "{}", None)
  |> expect.to_equal(Error(UnsafeOutputDir("/evil/path")))
}

pub fn write_rejects_parent_traversal_test() {
  output.write("../outside", "mypkg", "{}", None)
  |> expect.to_equal(Error(UnsafeOutputDir("../outside")))
}

// ─── write: missing module artifacts ────────────────────────────────────────

/// Creates a complete set of build artifacts for a test package + module.
/// Only creates prelude stubs if the files are absent to avoid contaminating
/// real build outputs. Returns the paths of any freshly created prelude stubs
/// so callers can delete them in teardown.
fn setup_full_artifacts(pkg: String, module: String) -> List(String) {
  let build_pkg = "build/dev/javascript/" <> pkg
  let build_parent = "build/dev/javascript"
  let _ = simplifile.create_directory_all(build_pkg)
  let _ = simplifile.create_directory_all(build_parent)
  let _ =
    simplifile.write(to: build_pkg <> "/" <> module <> ".mjs", contents: "")
  let _ =
    simplifile.write(to: build_pkg <> "/" <> module <> ".d.mts", contents: "")
  let _ = simplifile.write(to: build_pkg <> "/gleam.mjs", contents: "")
  let _ = simplifile.write(to: build_pkg <> "/gleam.d.mts", contents: "")
  // Create prelude stubs only when absent; return created paths for cleanup.
  list.filter_map(["prelude.mjs", "prelude.d.mts"], fn(file) {
    let path = build_parent <> "/" <> file
    case simplifile.is_file(path) {
      Ok(True) -> Error(Nil)
      _ -> {
        let _ = simplifile.write(to: path, contents: "")
        Ok(path)
      }
    }
  })
}

pub fn write_fails_when_module_mjs_missing_test() {
  let pkg = "talc_output_test_mjs"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, out])
  let prelude_stubs = setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.delete_file(build_pkg <> "/mymod.mjs")

  let result = output.write(out, pkg, "{}", Some(["mymod"]))

  let _ = simplifile.delete_all([build_pkg, out, ..prelude_stubs])
  result |> expect.to_be_error()
  Nil
}

pub fn write_fails_when_module_dts_missing_test() {
  let pkg = "talc_output_test_dts"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, out])
  let prelude_stubs = setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.delete_file(build_pkg <> "/mymod.d.mts")

  let result = output.write(out, pkg, "{}", Some(["mymod"]))

  let _ = simplifile.delete_all([build_pkg, out, ..prelude_stubs])
  result |> expect.to_be_error()
  Nil
}

pub fn write_fails_when_gleam_support_mjs_missing_test() {
  let pkg = "talc_output_test_gleam"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, out])
  let prelude_stubs = setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.delete_file(build_pkg <> "/gleam.mjs")

  let result = output.write(out, pkg, "{}", Some(["mymod"]))

  let _ = simplifile.delete_all([build_pkg, out, ..prelude_stubs])
  result |> expect.to_be_error()
  Nil
}

pub fn write_copies_dependency_javascript_artifacts_test() {
  let pkg = "talc_output_test_deps"
  let dep = "talc_output_dep"
  let build_pkg = "build/dev/javascript/" <> pkg
  let build_dep = "build/dev/javascript/" <> dep
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, build_dep, out])
  let prelude_stubs = setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.create_directory_all(build_dep <> "/nested")
  let _ = simplifile.write(to: build_dep <> "/nested/runtime.mjs", contents: "")
  let _ =
    simplifile.write(to: build_dep <> "/nested/runtime.d.mts", contents: "")

  let result = output.write(out, pkg, "{}", Some(["mymod"]))
  let copied_mjs =
    simplifile.is_file(out <> "/" <> dep <> "/nested/runtime.mjs")
  let copied_dts =
    simplifile.is_file(out <> "/" <> dep <> "/nested/runtime.d.mts")

  let _ = simplifile.delete_all([build_pkg, build_dep, out, ..prelude_stubs])
  result |> expect.to_be_ok()
  copied_mjs |> expect.to_equal(Ok(True))
  copied_dts |> expect.to_equal(Ok(True))
}

pub fn write_copies_private_modules_and_ffi_unchanged_test() {
  let pkg = "talc_output_test_native"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let prelude_stubs = setup_full_artifacts(pkg, "mymod")
  let artifacts = [
    #("internal.mjs", "export const value = 42;"),
    #("internal.d.mts", "export const value: number;"),
    #("ffi.js", "export const identity = value => value;"),
    #("ffi.d.ts", "export function identity<T>(value: T): T;"),
    #("external.d.mts", "export type Thing = { value: number };"),
  ]
  list.each(artifacts, fn(pair) {
    simplifile.write(to: build_pkg <> "/" <> pair.0, contents: pair.1)
    |> expect.to_be_ok()
  })
  output.write(out, pkg, "{}", Some(["mymod"])) |> expect.to_be_ok()
  let contents =
    list.map(artifacts, fn(pair) {
      #(simplifile.read(out <> "/dist/" <> pair.0), Ok(pair.1))
    })
  let _ = simplifile.delete_all([build_pkg, out, ..prelude_stubs])
  list.each(contents, fn(pair) { pair.0 |> expect.to_equal(pair.1) })
}

pub fn write_rejects_legacy_wrappers_without_overwriting_test() {
  let out = "test_work/talc_output_test_legacy"
  let legacy_dir = out <> "/dist/_wrapper"
  simplifile.create_directory_all(legacy_dir) |> expect.to_be_ok()
  simplifile.write(to: out <> "/package.json", contents: "original")
  |> expect.to_be_ok()
  let result = output.write(out, "unused", "replacement", None)
  let original = simplifile.read(out <> "/package.json")
  let _ = simplifile.delete_all([out])
  result |> expect.to_equal(Error(output.ExistingWrappers(legacy_dir)))
  original |> expect.to_equal(Ok("original"))
}

pub fn validate_output_dir_rejects_portable_unsafe_forms_test() {
  list.each(
    [
      ".", "./", "././", "//host/share", "\\\\host\\share", "\\rooted",
      "C:\\out", "C:/out", "C:out", "..\\outside", "foo\\..\\bar", "foo/..\\bar",
      "foo/../bar", "foo/.", "foo/ ", "foo./out", "out\u{0}side",
    ],
    fn(path) {
      // A trailing "." is valid for nested paths, but not a root alias.
      case path {
        "foo/." -> validate_output_dir(path) |> expect.to_equal(Ok(Nil))
        _ ->
          validate_output_dir(path)
          |> expect.to_equal(Error(UnsafeOutputDir(path)))
      }
    },
  )
}

pub fn write_rejects_symlinked_destinations_without_mutation_test() {
  let root = "test_work/talc_output_symlinks"
  let assert Ok(cwd) = simplifile.current_directory()
  let target = cwd <> "/" <> root <> "/target"
  simplifile.create_directory_all(root <> "/target") |> expect.to_be_ok()
  simplifile.write(to: target <> "/sentinel", contents: "unchanged")
  |> expect.to_be_ok()
  list.each(["root", "ancestor", "nested", "metadata", "dangling"], fn(name) {
    let out = root <> "/" <> name
    let link = case name {
      "ancestor" -> out <> "/parent"
      "nested" -> out <> "/dist"
      "metadata" -> out <> "/package.json"
      _ -> out
    }
    let destination = case name {
      "ancestor" -> link <> "/child"
      _ -> out
    }
    case name {
      "root" | "dangling" -> Nil
      _ -> simplifile.create_directory_all(out) |> expect.to_be_ok()
    }
    let link_target = case name {
      "dangling" -> target <> "/missing"
      "metadata" -> target <> "/sentinel"
      _ -> target
    }
    simplifile.create_symlink(link_target, link) |> expect.to_be_ok()
    output.write(destination, "unused", "replacement", None)
    |> expect.to_equal(Error(output.UnsafeFilesystemPath(link)))
    simplifile.read(target <> "/sentinel")
    |> expect.to_equal(Ok("unchanged"))
    simplifile.delete_file(link) |> expect.to_be_ok()
  })
  simplifile.delete(root) |> expect.to_be_ok()
}

pub fn write_rejects_symlinked_artifact_and_hardlink_test() {
  let pkg = "talc_output_links"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg
  let stubs = setup_full_artifacts(pkg, "mymod")
  simplifile.create_directory_all(out <> "/dist") |> expect.to_be_ok()
  simplifile.write(to: out <> "/sentinel", contents: "unchanged")
  |> expect.to_be_ok()
  let assert Ok(cwd) = simplifile.current_directory()
  let target = cwd <> "/" <> out <> "/sentinel"
  let dest = out <> "/dist/mymod.mjs"
  simplifile.create_symlink(target, dest) |> expect.to_be_ok()
  output.write(out, pkg, "replacement", Some(["mymod"]))
  |> expect.to_equal(Error(output.UnsafeFilesystemPath(dest)))
  simplifile.delete_file(dest) |> expect.to_be_ok()
  simplifile.create_link(target, dest) |> expect.to_be_ok()
  output.write(out, pkg, "replacement", Some(["mymod"]))
  |> expect.to_be_error()
  simplifile.read(target) |> expect.to_equal(Ok("unchanged"))
  simplifile.delete_all([build_pkg, out, ..stubs]) |> expect.to_be_ok()
}

pub fn write_rejects_stale_modules_and_dependencies_before_writes_test() {
  let pkg = "talc_output_repeat"
  let dep = "talc_output_removed_dependency"
  let build_pkg = "build/dev/javascript/" <> pkg
  let build_dep = "build/dev/javascript/" <> dep
  let out = "test_work/" <> pkg
  let fresh = out <> "_fresh"
  let stubs = setup_full_artifacts(pkg, "mymod")
  simplifile.create_directory_all(build_dep) |> expect.to_be_ok()
  simplifile.write(to: build_dep <> "/old.mjs", contents: "old dependency")
  |> expect.to_be_ok()
  simplifile.write(to: build_pkg <> "/private.mjs", contents: "old module")
  |> expect.to_be_ok()
  output.write(out, pkg, "original", Some(["mymod"])) |> expect.to_be_ok()
  simplifile.write(to: out <> "/notes.txt", contents: "user file")
  |> expect.to_be_ok()
  output.write(out, pkg, "original", Some(["mymod"])) |> expect.to_be_ok()
  simplifile.delete_file(build_pkg <> "/private.mjs") |> expect.to_be_ok()
  output.write(out, pkg, "replacement", Some(["mymod"]))
  |> expect.to_equal(Error(output.StaleOutput(out <> "/dist/private.mjs")))
  simplifile.read(out <> "/package.json") |> expect.to_equal(Ok("original"))
  simplifile.delete_file(out <> "/dist/private.mjs") |> expect.to_be_ok()
  simplifile.delete(build_dep) |> expect.to_be_ok()
  output.write(out, pkg, "replacement", Some(["mymod"]))
  |> expect.to_equal(Error(output.StaleOutput(out <> "/" <> dep <> "/old.mjs")))
  simplifile.read(out <> "/package.json") |> expect.to_equal(Ok("original"))
  simplifile.read(out <> "/notes.txt") |> expect.to_equal(Ok("user file"))
  output.write(fresh, pkg, "fresh", Some(["mymod"])) |> expect.to_be_ok()
  simplifile.is_file(fresh <> "/dist/private.mjs") |> expect.to_equal(Ok(False))
  simplifile.is_directory(fresh <> "/" <> dep) |> expect.to_equal(Ok(False))
  simplifile.delete_all([build_pkg, out, fresh, ..stubs]) |> expect.to_be_ok()
}
