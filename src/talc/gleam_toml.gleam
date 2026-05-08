/// Parsing and extraction of `gleam.toml` configuration.
///
/// This module reads a Gleam project's `gleam.toml` file and extracts
/// the metadata fields needed for npm package generation.
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom

/// Repository information from gleam.toml.
pub type Repository {
  Repository(type_: String, user: String, repo: String)
}

/// Parsed configuration from gleam.toml.
pub type GleamConfig {
  GleamConfig(
    name: String,
    version: String,
    description: String,
    licences: List(String),
    repository: Result(Repository, Nil),
  )
}

/// Errors that can occur when reading or parsing gleam.toml.
pub type ConfigError {
  FileError(message: String)
  ParseError(message: String)
  MissingField(field: String)
}

/// Reads and parses `gleam.toml` from the given directory.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(config) = read(".")
/// config.name
/// // -> "my_package"
/// ```
pub fn read(from directory: String) -> Result(GleamConfig, ConfigError) {
  let path = directory <> "/gleam.toml"
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { FileError("Could not read " <> path) }),
  )
  parse(content)
}

/// Parses a gleam.toml content string into a GleamConfig.
pub fn parse(content: String) -> Result(GleamConfig, ConfigError) {
  use toml <- result.try(
    tom.parse(content)
    |> result.map_error(fn(e) { ParseError(parse_error_to_string(e)) }),
  )

  use name <- result.try(get_required_string(toml, "name"))
  use version <- result.try(get_required_string(toml, "version"))

  let description =
    tom.get_string(toml, ["description"])
    |> result.unwrap("")

  let licences = get_licences(toml)
  let repository = get_repository(toml)

  Ok(GleamConfig(
    name: name,
    version: version,
    description: description,
    licences: licences,
    repository: repository,
  ))
}

fn get_required_string(
  toml: dict.Dict(String, tom.Toml),
  field: String,
) -> Result(String, ConfigError) {
  tom.get_string(toml, [field])
  |> result.map_error(fn(_) { MissingField(field) })
}

fn get_licences(toml: dict.Dict(String, tom.Toml)) -> List(String) {
  case tom.get_array(toml, ["licences"]) {
    Ok(items) ->
      list.filter_map(items, fn(item) {
        case item {
          tom.String(s) -> Ok(s)
          _ -> Error(Nil)
        }
      })
    Error(_) -> []
  }
}

fn get_repository(
  toml: dict.Dict(String, tom.Toml),
) -> Result(Repository, Nil) {
  use type_ <- result.try(
    tom.get_string(toml, ["repository", "type"])
    |> result.replace_error(Nil),
  )
  use user <- result.try(
    tom.get_string(toml, ["repository", "user"])
    |> result.replace_error(Nil),
  )
  use repo <- result.try(
    tom.get_string(toml, ["repository", "repo"])
    |> result.replace_error(Nil),
  )
  Ok(Repository(type_: type_, user: user, repo: repo))
}

fn parse_error_to_string(error: tom.ParseError) -> String {
  case error {
    tom.Unexpected(got, expected) ->
      "Unexpected '" <> got <> "', expected " <> expected
    tom.KeyAlreadyInUse(key) -> "Key already in use: " <> string.join(key, ".")
  }
}
