/// Loading the Gleam package interface via the compiler.
///
/// This module invokes `gleam export package-interface` and decodes the
/// resulting JSON into typed Gleam data structures.
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/package_interface.{type Module, type Package}
import gleam/result
import gleam/string
import simplifile

/// Loads the package interface by invoking the Gleam compiler.
///
/// Runs `gleam export package-interface --out <tmpfile>`, reads the
/// output JSON, and decodes it into a `Package`.
pub fn load() -> Result(Package, String) {
  let tmp_path = temp_path()

  use exit_code <- result.try(
    run_gleam_export(tmp_path)
    |> result.map_error(fn(_) {
      "Failed to run `gleam export package-interface`"
    }),
  )

  use _ <- result.try(case exit_code {
    0 -> Ok(Nil)
    _ ->
      Error(
        "`gleam export package-interface` failed with exit code "
        <> int.to_string(exit_code),
      )
  })

  use json_content <- result.try(
    simplifile.read(tmp_path)
    |> result.map_error(fn(_) {
      "Failed to read package interface output at " <> tmp_path
    }),
  )

  // Clean up temp file
  let _ = simplifile.delete(tmp_path)

  use package <- result.try(
    json.parse(json_content, package_interface.decoder())
    |> result.map_error(fn(_) { "Failed to decode package interface JSON" }),
  )

  Ok(package)
}

/// Returns the list of public module names from a package.
pub fn public_module_names(package: Package) -> List(String) {
  dict.keys(package.modules)
}

/// Returns a specific module from the package, if it exists.
pub fn get_module(package: Package, name: String) -> Result(Module, Nil) {
  dict.get(package.modules, name)
}

/// Checks if a module can run on JavaScript based on its functions.
/// A module is JS-compatible if it has at least one function that
/// can run on JavaScript.
pub fn module_has_js_support(module: Module) -> Bool {
  dict.values(module.functions)
  |> list.any(fn(func) { func.implementations.can_run_on_javascript })
}

/// Converts a module name to a relative .mjs path.
/// e.g. "birch/handler" → "birch/handler.mjs"
pub fn module_to_mjs_path(module_name: String) -> String {
  string.replace(module_name, "/", "/") <> ".mjs"
}

/// Converts a module name to a relative .d.ts path.
/// e.g. "birch/handler" → "birch/handler.d.ts"
pub fn module_to_dts_path(module_name: String) -> String {
  string.replace(module_name, "/", "/") <> ".d.ts"
}

// -- Internals --

fn temp_path() -> String {
  "/tmp/talc_package_interface_" <> random_id() <> ".json"
}

@external(erlang, "talc_interface_ffi", "run_gleam_export")
fn run_gleam_export(out_path: String) -> Result(Int, Nil)

@external(erlang, "talc_interface_ffi", "random_id")
fn random_id() -> String
