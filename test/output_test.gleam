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
  output.write("/evil/path", "mypkg", "{}", None, [])
  |> expect.to_equal(Error(UnsafeOutputDir("/evil/path")))
}

pub fn write_rejects_parent_traversal_test() {
  output.write("../outside", "mypkg", "{}", None, [])
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

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])

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

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])

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

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])

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

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])
  let copied_mjs =
    simplifile.is_file(out <> "/" <> dep <> "/nested/runtime.mjs")
  let copied_dts =
    simplifile.is_file(out <> "/" <> dep <> "/nested/runtime.d.mts")

  let _ = simplifile.delete_all([build_pkg, build_dep, out, ..prelude_stubs])
  result |> expect.to_be_ok()
  copied_mjs |> expect.to_equal(Ok(True))
  copied_dts |> expect.to_equal(Ok(True))
}
