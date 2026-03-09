/// Parsing of optional `talc.toml` configuration overrides.
///
/// This module reads the optional `talc.toml` sidecar file that allows
/// authors to override or extend generated package.json fields.
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile
import tom

/// Package-level configuration overrides.
pub type PackageConfig {
  PackageConfig(
    scope: Option(String),
    version: Option(String),
    registry: Option(String),
    output_dir: String,
  )
}

/// Parsed talc.toml configuration.
pub type TalcConfig {
  TalcConfig(
    package: PackageConfig,
    extra_fields: List(#(String, String)),
    peer_dependencies: List(#(String, String)),
  )
}

/// Returns a TalcConfig with all default values.
pub fn default() -> TalcConfig {
  TalcConfig(
    package: PackageConfig(
      scope: None,
      version: None,
      registry: None,
      output_dir: "npm_dist",
    ),
    extra_fields: [],
    peer_dependencies: [],
  )
}

/// Reads and parses `talc.toml` from the given directory.
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
  let path = directory <> "/talc.toml"
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

/// Parses a talc.toml content string into a TalcConfig.
pub fn parse(content: String) -> Result(TalcConfig, String) {
  use toml <- result.try(
    tom.parse(content)
    |> result.map_error(fn(_) { "Failed to parse talc.toml" }),
  )

  let package = parse_package(toml)
  let extra_fields = parse_extra_fields(toml)
  let peer_dependencies = parse_peer_dependencies(toml)

  Ok(TalcConfig(
    package: package,
    extra_fields: extra_fields,
    peer_dependencies: peer_dependencies,
  ))
}

fn parse_package(toml: dict.Dict(String, tom.Toml)) -> PackageConfig {
  let scope = case tom.get_string(toml, ["package", "scope"]) {
    Ok(s) -> Some(s)
    Error(_) -> None
  }

  let version = case tom.get_string(toml, ["package", "version"]) {
    Ok(s) -> Some(s)
    Error(_) -> None
  }

  let registry = case tom.get_string(toml, ["package", "registry"]) {
    Ok(s) -> Some(s)
    Error(_) -> None
  }

  let output_dir = case tom.get_string(toml, ["package", "output_dir"]) {
    Ok(s) -> s
    Error(_) -> "npm_dist"
  }

  PackageConfig(
    scope: scope,
    version: version,
    registry: registry,
    output_dir: output_dir,
  )
}

fn parse_extra_fields(
  toml: dict.Dict(String, tom.Toml),
) -> List(#(String, String)) {
  case tom.get_table(toml, ["package", "json"]) {
    Ok(table) ->
      dict.to_list(table)
      |> list.filter_map(fn(pair) {
        case pair {
          #(key, tom.String(value)) -> Ok(#(key, value))
          _ -> Error(Nil)
        }
      })
    Error(_) -> []
  }
}

fn parse_peer_dependencies(
  toml: dict.Dict(String, tom.Toml),
) -> List(#(String, String)) {
  case tom.get_table(toml, ["peer_dependencies"]) {
    Ok(table) ->
      dict.to_list(table)
      |> list.filter_map(fn(pair) {
        case pair {
          #(key, tom.String(value)) -> Ok(#(key, value))
          _ -> Error(Nil)
        }
      })
    Error(_) -> []
  }
}
