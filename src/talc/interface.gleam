/// Loading the Gleam package interface via the compiler.
///
/// This module invokes `gleam export package-interface` and decodes the
/// resulting JSON into typed Gleam data structures.
import gleam/dict
import gleam/int
import gleam/json
import gleam/package_interface.{type Package}
import gleam/result
import gleam/string
import simplifile

/// Failures to obtain or decode the compiler's package interface.
pub type LoadError {
  NotFound
  TimedOut
  CommandFailed(exit_code: Int, output: String)
  ReadFailed(path: String, detail: String)
  DecodeFailed(detail: String)
}

/// Formats the specific interface failure for CLI reports.
pub fn error_to_string(error: LoadError) -> String {
  case error {
    NotFound -> "gleam executable not found in PATH"
    TimedOut -> "Timed out running `gleam export package-interface`"
    CommandFailed(code, output) ->
      "`gleam export package-interface` failed with exit code "
      <> int.to_string(code)
      <> ":\n"
      <> string.trim(output)
    ReadFailed(path, detail) ->
      "Failed to read package interface output at " <> path <> ": " <> detail
    DecodeFailed(detail) ->
      "Failed to decode package interface JSON: " <> detail
  }
}

/// Loads the package interface by invoking the Gleam compiler.
///
/// Runs `gleam export package-interface --out <tmpfile>`, reads the
/// output JSON, and decodes it into a `Package`.
pub fn load() -> Result(Package, LoadError) {
  let tmp_path = temp_path()

  use #(exit_code, output) <- result.try(case run_gleam_export(tmp_path) {
    Ok(result) -> Ok(result)
    Error(RunNotFound) -> {
      let _ = simplifile.delete(tmp_path)
      Error(NotFound)
    }
    Error(RunTimeout) -> {
      let _ = simplifile.delete(tmp_path)
      Error(TimedOut)
    }
  })

  use _ <- result.try(case exit_code {
    0 -> Ok(Nil)
    _ -> {
      let _ = simplifile.delete(tmp_path)
      Error(CommandFailed(exit_code, output))
    }
  })

  let read_result =
    simplifile.read(tmp_path)
    |> result.map_error(fn(error) {
      ReadFailed(tmp_path, simplifile.describe_error(error))
    })

  // Clean up temp file on all paths after successful export
  let _ = simplifile.delete(tmp_path)

  use json_content <- result.try(read_result)

  use package <- result.try(
    json.parse(json_content, package_interface.decoder())
    |> result.map_error(fn(error) { DecodeFailed(string.inspect(error)) }),
  )

  Ok(package)
}

/// Returns the list of public module names from a package.
pub fn public_module_names(package: Package) -> List(String) {
  dict.keys(package.modules)
}

// -- Internals --

type InterfaceRunError {
  RunNotFound
  RunTimeout
}

fn temp_path() -> String {
  ".talc_pkg_iface_" <> random_id() <> ".json"
}

@external(erlang, "talc_interface_ffi", "run_gleam_export")
fn run_gleam_export(
  out_path: String,
) -> Result(#(Int, String), InterfaceRunError)

@external(erlang, "talc_interface_ffi", "random_id")
fn random_id() -> String
