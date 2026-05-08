import gleam/json
import gleam/option.{None, Some}
import gleam/string
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

pub fn parse_empty_ccl_test() {
  let config = talc_config.parse("") |> expect.to_be_ok()
  config.package.scope |> expect.to_equal(None)
  config.package.output_dir |> expect.to_equal("npm_dist")
}

pub fn parse_package_section_test() {
  let ccl =
    "package =
  scope = @myorg
  registry = https://registry.npmjs.org
  output_dir = dist_out
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  config.package.scope |> expect.to_equal(Some("@myorg"))
  config.package.registry
  |> expect.to_equal(Some("https://registry.npmjs.org"))
  config.package.output_dir |> expect.to_equal("dist_out")
}

pub fn parse_extra_fields_test() {
  let ccl =
    "package.json =
  homepage = https://example.com
  author = gleam-team
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  let assert [_, _] = config.extra_fields
  Nil
}

pub fn parse_extra_fields_mixed_types_test() {
  let ccl =
    "package.json =
  private = true
  version = 2.0.0
  keywords =
    = gleam
    = beam
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()

  // Verify the values are correctly converted to JSON
  let json_str =
    config.extra_fields
    |> json.object()
    |> json.to_string()

  json_str
  |> expect_string_contains("\"private\":true")
  // version contains a dot so won't parse as int/float, stays as string
  json_str
  |> expect_string_contains("\"version\":\"2.0.0\"")
  json_str
  |> expect_string_contains("\"keywords\"")
  json_str
  |> expect_string_contains("\"gleam\"")
}

pub fn parse_extra_fields_nested_object_test() {
  let ccl =
    "package.json =
  author =
    name = Test Author
    email = test@example.com
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()

  let json_str =
    config.extra_fields
    |> json.object()
    |> json.to_string()

  json_str
  |> expect_string_contains("\"author\"")
  json_str
  |> expect_string_contains("\"Test Author\"")
}

pub fn parse_extra_fields_boolean_coercion_test() {
  let ccl =
    "package.json =
  private = true
  sideEffects = false
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()

  let json_str =
    config.extra_fields
    |> json.object()
    |> json.to_string()

  json_str
  |> expect_string_contains("\"private\":true")
  json_str
  |> expect_string_contains("\"sideEffects\":false")
}

pub fn parse_extra_fields_integer_coercion_test() {
  let ccl =
    "package.json =
  retryCount = 3
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()

  let json_str =
    config.extra_fields
    |> json.object()
    |> json.to_string()

  json_str
  |> expect_string_contains("\"retryCount\":3")
}

fn expect_string_contains(haystack: String, needle: String) -> Nil {
  string.contains(haystack, needle)
  |> expect.to_be_true()
}

pub fn parse_peer_dependencies_test() {
  let ccl =
    "peer_dependencies =
  react = >=18
  react-dom = >=18
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  let assert [_, _] = config.peer_dependencies
  Nil
}

pub fn parse_full_config_test() {
  let ccl =
    "package =
  scope = @gleam
  output_dir = npm_out

package.json =
  homepage = https://gleam.run

peer_dependencies =
  vite = >=5
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  config.package.scope |> expect.to_equal(Some("@gleam"))
  config.package.output_dir |> expect.to_equal("npm_out")
  let assert [_] = config.extra_fields
  let assert [_] = config.peer_dependencies
  Nil
}

pub fn default_use_true_myth_test() {
  let config = talc_config.default()
  config.use_true_myth |> expect.to_be_true()
}

pub fn parse_use_true_myth_default_test() {
  let config = talc_config.parse("") |> expect.to_be_ok()
  config.use_true_myth |> expect.to_be_true()
}

pub fn parse_use_true_myth_explicit_true_test() {
  let ccl =
    "package =
  use_true_myth = true
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  config.use_true_myth |> expect.to_be_true()
}

pub fn parse_use_true_myth_false_test() {
  let ccl =
    "package =
  use_true_myth = false
"

  let config = talc_config.parse(ccl) |> expect.to_be_ok()
  config.use_true_myth |> expect.to_be_false()
}
