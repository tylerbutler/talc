/// Tests for output directory validation and required artifact checking.
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
fn setup_full_artifacts(pkg: String, module: String) -> Nil {
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
  let _ = simplifile.write(to: build_parent <> "/prelude.mjs", contents: "")
  let _ = simplifile.write(to: build_parent <> "/prelude.d.mts", contents: "")
  Nil
}

pub fn write_fails_when_module_mjs_missing_test() {
  let pkg = "talc_output_test_mjs"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, out])
  setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.delete_file(build_pkg <> "/mymod.mjs")

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])

  let _ = simplifile.delete_all([build_pkg, out])
  result |> expect.to_be_error()
  Nil
}

pub fn write_fails_when_module_dts_missing_test() {
  let pkg = "talc_output_test_dts"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, out])
  setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.delete_file(build_pkg <> "/mymod.d.mts")

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])

  let _ = simplifile.delete_all([build_pkg, out])
  result |> expect.to_be_error()
  Nil
}

pub fn write_fails_when_gleam_support_mjs_missing_test() {
  let pkg = "talc_output_test_gleam"
  let build_pkg = "build/dev/javascript/" <> pkg
  let out = "test_work/" <> pkg <> "_out"
  let _ = simplifile.delete_all([build_pkg, out])
  setup_full_artifacts(pkg, "mymod")
  let _ = simplifile.delete_file(build_pkg <> "/gleam.mjs")

  let result = output.write(out, pkg, "{}", Some(["mymod"]), [])

  let _ = simplifile.delete_all([build_pkg, out])
  result |> expect.to_be_error()
  Nil
}
