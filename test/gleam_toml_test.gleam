import startest/expect
import talc/gleam_toml

pub fn parse_minimal_gleam_toml_test() {
  let toml =
    "name = \"my_lib\"
version = \"1.0.0\"
"

  let config = gleam_toml.parse(toml) |> expect.to_be_ok()
  config.name |> expect.to_equal("my_lib")
  config.version |> expect.to_equal("1.0.0")
  config.description |> expect.to_equal("")
  config.licences |> expect.to_equal([])
  let _ = config.repository |> expect.to_be_error()
  Nil
}

pub fn parse_full_gleam_toml_test() {
  let toml =
    "name = \"gleam_utils\"
version = \"2.3.1\"
description = \"Utility functions\"
licences = [\"MIT\", \"Apache-2.0\"]

[repository]
type = \"github\"
user = \"myorg\"
repo = \"gleam_utils\"
"

  let config = gleam_toml.parse(toml) |> expect.to_be_ok()
  config.name |> expect.to_equal("gleam_utils")
  config.version |> expect.to_equal("2.3.1")
  config.description |> expect.to_equal("Utility functions")
  config.licences |> expect.to_equal(["MIT", "Apache-2.0"])

  let assert Ok(repo) = config.repository
  repo.type_ |> expect.to_equal("github")
  repo.user |> expect.to_equal("myorg")
  repo.repo |> expect.to_equal("gleam_utils")
}

pub fn parse_missing_name_test() {
  let toml = "version = \"1.0.0\"\n"

  let err = gleam_toml.parse(toml) |> expect.to_be_error()
  case err {
    gleam_toml.MissingField("name") -> Nil
    _ -> panic as "Expected MissingField(name)"
  }
}

pub fn parse_missing_version_test() {
  let toml = "name = \"test\"\n"

  let err = gleam_toml.parse(toml) |> expect.to_be_error()
  case err {
    gleam_toml.MissingField("version") -> Nil
    _ -> panic as "Expected MissingField(version)"
  }
}

pub fn parse_invalid_toml_test() {
  let err = gleam_toml.parse("[[[[invalid") |> expect.to_be_error()
  case err {
    gleam_toml.ParseError(_) -> Nil
    _ -> panic as "Expected ParseError"
  }
}

pub fn parse_partial_repository_test() {
  let toml =
    "name = \"test\"
version = \"1.0.0\"

[repository]
type = \"github\"
"

  let config = gleam_toml.parse(toml) |> expect.to_be_ok()
  let _ = config.repository |> expect.to_be_error()
  Nil
}
