/// Parsing of optional `talc.ccl` configuration overrides.
///
/// This module reads the optional `talc.ccl` sidecar file that allows
/// authors to override or extend generated package.json fields.
/// Uses the CCL (Categorical Configuration Language) format.
import ccl/access
import ccl/hierarchy
import ccl/parser
import ccl/types.{type CCL, type CCLValue, CclList, CclObject, CclString}
import gleam/dict
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

/// Package-level configuration overrides.
pub type PackageConfig {
  PackageConfig(
    scope: Option(String),
    registry: Option(String),
    output_dir: String,
  )
}

/// Parsed talc.ccl configuration.
pub type TalcConfig {
  TalcConfig(
    package: PackageConfig,
    extra_fields: List(#(String, json.Json)),
    peer_dependencies: List(#(String, String)),
    /// Directory to scan for external type declaration files (.d.mts).
    /// Defaults to "talc-types".
    type_declarations_dir: String,
    /// When True, generate wrapper modules that convert top-level Result/Option
    /// to true-myth types. Adds true-myth as a peer dependency.
    use_true_myth: Bool,
  )
}

/// Returns a TalcConfig with all default values.
pub fn default() -> TalcConfig {
  TalcConfig(
    package: PackageConfig(scope: None, registry: None, output_dir: "npm_dist"),
    extra_fields: [],
    peer_dependencies: [],
    type_declarations_dir: "talc-types",
    use_true_myth: True,
  )
}

/// Reads and parses `talc.ccl` from the given directory.
/// Returns the default config if the file does not exist.
///
/// ## Examples
///
/// ```gleam
/// let config = read(".")
/// config.package.output_dir
/// // -> "npm_dist"
/// ```
pub fn read(from directory: String) -> Result(TalcConfig, String) {
  let path = directory <> "/talc.ccl"
  case simplifile.is_file(path) {
    Ok(True) -> {
      use content <- result.try(
        simplifile.read(path)
        |> result.map_error(fn(_) { "Could not read " <> path }),
      )
      parse(content)
    }
    _ -> Ok(default())
  }
}

/// Parses a talc.ccl content string into a TalcConfig.
pub fn parse(content: String) -> Result(TalcConfig, String) {
  use entries <- result.try(
    parser.parse(content)
    |> result.map_error(fn(_) { "Failed to parse talc.ccl" }),
  )

  let ccl = hierarchy.build_hierarchy(entries)

  let package = parse_package(ccl)
  let extra_fields = parse_extra_fields(ccl)
  let peer_dependencies = parse_peer_dependencies(ccl)
  let type_declarations_dir = parse_type_declarations_dir(ccl)
  let use_true_myth = parse_use_true_myth(ccl)

  Ok(TalcConfig(
    package: package,
    extra_fields: extra_fields,
    peer_dependencies: peer_dependencies,
    type_declarations_dir: type_declarations_dir,
    use_true_myth: use_true_myth,
  ))
}

fn parse_package(ccl: CCL) -> PackageConfig {
  let scope = case access.get_string(ccl, ["package", "scope"]) {
    Ok(s) -> Some(s)
    Error(_) -> None
  }

  let registry = case access.get_string(ccl, ["package", "registry"]) {
    Ok(s) -> Some(s)
    Error(_) -> None
  }

  let output_dir = case access.get_string(ccl, ["package", "output_dir"]) {
    Ok(s) -> s
    Error(_) -> "npm_dist"
  }

  PackageConfig(scope: scope, registry: registry, output_dir: output_dir)
}

fn parse_extra_fields(ccl: CCL) -> List(#(String, json.Json)) {
  case dict.get(ccl, "package.json") {
    Ok(CclObject(table)) ->
      dict.to_list(table)
      |> list.map(fn(pair) { #(pair.0, ccl_value_to_json(pair.1)) })
    _ -> []
  }
}

/// Converts a CCL value to a JSON value with smart type coercion.
/// String values are coerced: "true"/"false" → bool, numeric strings → int/float.
/// CCL lists (represented as CclObject with empty key) are unwrapped to JSON arrays.
pub fn ccl_value_to_json(value: CCLValue) -> json.Json {
  case value {
    CclString(s) -> coerce_string_to_json(s)
    CclList(items) ->
      json.preprocessed_array(list.map(items, ccl_value_to_json))
    // CCL represents lists as CclObject with a single "" key containing a CclList
    CclObject(obj) ->
      case dict.to_list(obj) {
        [#("", CclList(items))] ->
          json.preprocessed_array(list.map(items, ccl_value_to_json))
        pairs ->
          json.object(
            list.map(pairs, fn(pair) { #(pair.0, ccl_value_to_json(pair.1)) }),
          )
      }
  }
}

/// Attempts to coerce a string to a more specific JSON type.
fn coerce_string_to_json(s: String) -> json.Json {
  case s {
    "true" -> json.bool(True)
    "false" -> json.bool(False)
    _ ->
      case int.parse(s) {
        Ok(n) -> json.int(n)
        Error(_) ->
          case float.parse(s) {
            Ok(f) -> json.float(f)
            Error(_) -> json.string(s)
          }
      }
  }
}

fn parse_peer_dependencies(ccl: CCL) -> List(#(String, String)) {
  case dict.get(ccl, "peer_dependencies") {
    Ok(CclObject(table)) ->
      dict.to_list(table)
      |> list.filter_map(fn(pair) {
        case pair {
          #(key, CclString(value)) -> Ok(#(key, value))
          _ -> Error(Nil)
        }
      })
    _ -> []
  }
}

fn parse_type_declarations_dir(ccl: CCL) -> String {
  case access.get_string(ccl, ["type_declarations_dir"]) {
    Ok(s) -> s
    Error(_) -> "talc-types"
  }
}

fn parse_use_true_myth(ccl: CCL) -> Bool {
  case access.get_string(ccl, ["package", "use_true_myth"]) {
    Ok("false") -> False
    _ -> True
  }
}
