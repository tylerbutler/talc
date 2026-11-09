/// Parsing of optional `talc.ccl` configuration overrides.
///
/// This module reads the optional `talc.ccl` sidecar file that allows
/// authors to override or extend generated package.json fields.
/// Uses the CCL (Categorical Configuration Language) format.
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
    /// When True, the user opts in to lifecycle script execution: `scripts`
    /// from `[package.json]` are kept in the generated package.json, and
    /// `npm pack`/`npm publish` are invoked WITHOUT `--ignore-scripts`.
    /// Defaults to False — a malicious release PR cannot land arbitrary
    /// `prepublishOnly`/`prepare` code paths via `talc.ccl`.
    unsafe_allow_scripts: Bool,
  )
}

/// Parsed talc.ccl configuration.
pub type TalcConfig {
  TalcConfig(
    package: PackageConfig,
    extra_fields: List(#(String, json.Json)),
    peer_dependencies: List(#(String, String)),
  )
}

/// Returns a TalcConfig with all default values.
pub fn default() -> TalcConfig {
  TalcConfig(
    package: PackageConfig(
      scope: None,
      registry: None,
      output_dir: "npm_dist",
      unsafe_allow_scripts: False,
    ),
    extra_fields: [],
    peer_dependencies: [],
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
  case simplifile.link_info(path) {
    Ok(_) -> {
      use content <- result.try(
        simplifile.read(path)
        |> result.map_error(fn(error) {
          "Could not read " <> path <> ": " <> simplifile.describe_error(error)
        }),
      )
      parse(content)
    }
    Error(simplifile.Enoent) -> Ok(default())
    Error(error) ->
      Error(
        "Could not inspect " <> path <> ": " <> simplifile.describe_error(error),
      )
  }
}

/// Parses a talc.ccl content string into a TalcConfig.
pub fn parse(content: String) -> Result(TalcConfig, String) {
  use entries <- result.try(
    parser.parse(content)
    |> result.map_error(fn(_) { "Failed to parse talc.ccl" }),
  )

  let ccl = hierarchy.build_hierarchy(entries)

  use _ <- result.try(case dict.get(ccl, "package") {
    Ok(CclObject(fields)) ->
      case dict.has_key(fields, "use_true_myth") {
        True ->
          Error(
            "package.use_true_myth is no longer supported. Remove it from talc.ccl; talc packages native Gleam types.",
          )
        False -> Ok(Nil)
      }
    _ -> Ok(Nil)
  })

  use package <- result.try(parse_package(ccl))
  use extra_fields <- result.try(parse_extra_fields(ccl))
  use peer_dependencies <- result.try(parse_peer_dependencies(ccl))

  Ok(TalcConfig(
    package: package,
    extra_fields: extra_fields,
    peer_dependencies: peer_dependencies,
  ))
}

fn section(ccl: CCL, key: String) -> Result(CCL, String) {
  case dict.get(ccl, key) {
    Error(_) -> Ok(dict.new())
    Ok(CclObject(fields)) -> Ok(fields)
    Ok(_) -> Error("talc.ccl " <> key <> " must be a section")
  }
}

fn optional_string(fields: CCL, key: String) -> Result(Option(String), String) {
  case dict.get(fields, key) {
    Error(_) -> Ok(None)
    Ok(CclString(value)) -> Ok(Some(value))
    Ok(_) -> Error("talc.ccl package." <> key <> " must be a string")
  }
}

fn parse_package(ccl: CCL) -> Result(PackageConfig, String) {
  use fields <- result.try(section(ccl, "package"))
  use scope <- result.try(optional_string(fields, "scope"))
  use registry <- result.try(optional_string(fields, "registry"))
  use output_dir <- result.try(optional_string(fields, "output_dir"))
  use scripts <- result.try(optional_string(fields, "unsafe_allow_scripts"))
  use unsafe_allow_scripts <- result.try(case scripts {
    None | Some("false") -> Ok(False)
    Some("true") -> Ok(True)
    Some(_) ->
      Error("talc.ccl package.unsafe_allow_scripts must be true or false")
  })

  Ok(PackageConfig(
    scope: scope,
    registry: registry,
    output_dir: option.unwrap(output_dir, "npm_dist"),
    unsafe_allow_scripts: unsafe_allow_scripts,
  ))
}

fn parse_extra_fields(ccl: CCL) -> Result(List(#(String, json.Json)), String) {
  use table <- result.try(section(ccl, "package.json"))
  Ok(
    dict.to_list(table)
    |> list.map(fn(pair) { #(pair.0, ccl_value_to_json(pair.1)) }),
  )
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

fn parse_peer_dependencies(
  ccl: CCL,
) -> Result(List(#(String, String)), String) {
  use table <- result.try(section(ccl, "peer_dependencies"))
  dict.to_list(table)
  |> list.try_map(fn(pair) {
    case pair {
      #(key, CclString(value)) -> Ok(#(key, value))
      #(key, _) ->
        Error("talc.ccl peer_dependencies." <> key <> " must be a string")
    }
  })
}
