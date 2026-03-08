import gleeunit/should
import talc/gleam_toml

pub fn parse_minimal_gleam_toml_test() {
  let toml =
    "name = \"my_lib\"
version = \"1.0.0\"
"

  gleam_toml.parse(toml)
  |> should.be_ok()
  |> fn(config: gleam_toml.GleamConfig) {
    config.name |> should.equal("my_lib")
    config.version |> should.equal("1.0.0")
    config.description |> should.equal("")
    config.licences |> should.equal([])
    config.repository |> should.be_error()
  }
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

  gleam_toml.parse(toml)
  |> should.be_ok()
  |> fn(config: gleam_toml.GleamConfig) {
    config.name |> should.equal("gleam_utils")
    config.version |> should.equal("2.3.1")
    config.description |> should.equal("Utility functions")
    config.licences |> should.equal(["MIT", "Apache-2.0"])

    let assert Ok(repo) = config.repository
    repo.type_ |> should.equal("github")
    repo.user |> should.equal("myorg")
    repo.repo |> should.equal("gleam_utils")
  }
}

pub fn parse_missing_name_test() {
  let toml = "version = \"1.0.0\"\n"

  gleam_toml.parse(toml)
  |> should.be_error()
  |> fn(err) {
    case err {
      gleam_toml.MissingField("name") -> Nil
      _ -> panic as "Expected MissingField(name)"
    }
  }
}

pub fn parse_missing_version_test() {
  let toml = "name = \"test\"\n"

  gleam_toml.parse(toml)
  |> should.be_error()
  |> fn(err) {
    case err {
      gleam_toml.MissingField("version") -> Nil
      _ -> panic as "Expected MissingField(version)"
    }
  }
}

pub fn parse_invalid_toml_test() {
  gleam_toml.parse("[[[[invalid")
  |> should.be_error()
  |> fn(err) {
    case err {
      gleam_toml.ParseError(_) -> Nil
      _ -> panic as "Expected ParseError"
    }
  }
}

pub fn parse_partial_repository_test() {
  let toml =
    "name = \"test\"
version = \"1.0.0\"

[repository]
type = \"github\"
"

  gleam_toml.parse(toml)
  |> should.be_ok()
  |> fn(config: gleam_toml.GleamConfig) {
    config.repository |> should.be_error()
  }
}
