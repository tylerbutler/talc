import gleam/option.{None, Some}
import startest/expect
import talc/talc_config

pub fn default_config_test() {
  let config = talc_config.default()
  config.package.scope |> expect.to_equal(None)
  config.package.registry |> expect.to_equal(None)
  config.package.output_dir |> expect.to_equal("npm_dist")
  config.extra_fields |> expect.to_equal([])
  config.peer_dependencies |> expect.to_equal([])
}

pub fn parse_empty_toml_test() {
  let config = talc_config.parse("") |> expect.to_be_ok()
  config.package.scope |> expect.to_equal(None)
  config.package.output_dir |> expect.to_equal("npm_dist")
}

pub fn parse_package_section_test() {
  let toml =
    "[package]
scope = \"@myorg\"
registry = \"https://registry.npmjs.org\"
output_dir = \"dist_out\"
"

  let config = talc_config.parse(toml) |> expect.to_be_ok()
  config.package.scope |> expect.to_equal(Some("@myorg"))
  config.package.registry
  |> expect.to_equal(Some("https://registry.npmjs.org"))
  config.package.output_dir |> expect.to_equal("dist_out")
}

pub fn parse_extra_fields_test() {
  let toml =
    "[package.json]
homepage = \"https://example.com\"
keywords = \"gleam,functional\"
"

  let config = talc_config.parse(toml) |> expect.to_be_ok()
  let assert [_, _] = config.extra_fields
  Nil
}

pub fn parse_peer_dependencies_test() {
  let toml =
    "[peer_dependencies]
react = \">=18\"
\"react-dom\" = \">=18\"
"

  let config = talc_config.parse(toml) |> expect.to_be_ok()
  let assert [_, _] = config.peer_dependencies
  Nil
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

  let config = talc_config.parse(toml) |> expect.to_be_ok()
  config.package.scope |> expect.to_equal(Some("@gleam"))
  config.package.output_dir |> expect.to_equal("npm_out")
  let assert [_] = config.extra_fields
  let assert [_] = config.peer_dependencies
  Nil
}
