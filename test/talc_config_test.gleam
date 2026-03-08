import gleam/option.{None, Some}
import gleeunit/should
import talc/talc_config

pub fn default_config_test() {
  let config = talc_config.default()
  config.package.scope |> should.equal(None)
  config.package.registry |> should.equal(None)
  config.package.output_dir |> should.equal("npm_dist")
  config.extra_fields |> should.equal([])
  config.peer_dependencies |> should.equal([])
}

pub fn parse_empty_toml_test() {
  talc_config.parse("")
  |> should.be_ok()
  |> fn(config: talc_config.TalcConfig) {
    config.package.scope |> should.equal(None)
    config.package.output_dir |> should.equal("npm_dist")
  }
}

pub fn parse_package_section_test() {
  let toml =
    "[package]
scope = \"@myorg\"
registry = \"https://registry.npmjs.org\"
output_dir = \"dist_out\"
"

  talc_config.parse(toml)
  |> should.be_ok()
  |> fn(config: talc_config.TalcConfig) {
    config.package.scope |> should.equal(Some("@myorg"))
    config.package.registry
    |> should.equal(Some("https://registry.npmjs.org"))
    config.package.output_dir |> should.equal("dist_out")
  }
}

pub fn parse_extra_fields_test() {
  let toml =
    "[package.json]
homepage = \"https://example.com\"
keywords = \"gleam,functional\"
"

  talc_config.parse(toml)
  |> should.be_ok()
  |> fn(config: talc_config.TalcConfig) {
    let assert [_, _] = config.extra_fields
    Nil
  }
}

pub fn parse_peer_dependencies_test() {
  let toml =
    "[peer_dependencies]
react = \">=18\"
\"react-dom\" = \">=18\"
"

  talc_config.parse(toml)
  |> should.be_ok()
  |> fn(config: talc_config.TalcConfig) {
    let assert [_, _] = config.peer_dependencies
    Nil
  }
}

pub fn parse_full_config_test() {
  let toml =
    "[package]
scope = \"@gleam\"
output_dir = \"npm_out\"

[package.json]
homepage = \"https://gleam.run\"

[peer_dependencies]
vite = \">=5\"
"

  talc_config.parse(toml)
  |> should.be_ok()
  |> fn(config: talc_config.TalcConfig) {
    config.package.scope |> should.equal(Some("@gleam"))
    config.package.output_dir |> should.equal("npm_out")
    let assert [_] = config.extra_fields
    let assert [_] = config.peer_dependencies
    Nil
  }
}
