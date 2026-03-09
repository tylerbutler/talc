import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
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

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> should.not_equal("")
    // Check required fields are present
    json |> string_contains("\"name\":\"my_lib\"") |> should.be_true()
    json |> string_contains("\"version\":\"1.0.0\"") |> should.be_true()
    json |> string_contains("\"type\":\"module\"") |> should.be_true()
    json |> string_contains("\"license\":\"MIT\"") |> should.be_true()
  }
}

pub fn generate_esm_exports_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("./dist/my_lib.mjs") |> should.be_true()
    json |> string_contains("./dist/my_lib.d.ts") |> should.be_true()
    json |> string_contains("\"exports\"") |> should.be_true()
  }
}

pub fn generate_with_scope_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(
        scope: Some("@myorg"),
        version: None,
        registry: None,
        output_dir: "npm_dist",
      ),
    )

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"name\":\"@myorg/my_lib\"") |> should.be_true()
  }
}

pub fn generate_repository_github_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json
    |> string_contains("https://github.com/myorg/my_lib")
    |> should.be_true()
  }
}

pub fn generate_no_repository_test() {
  let gleam = GleamConfig(..test_gleam_config(), repository: Error(Nil))
  let talc = test_talc_config()

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"repository\"") |> should.be_false()
  }
}

pub fn generate_no_description_test() {
  let gleam = GleamConfig(..test_gleam_config(), description: "")
  let talc = test_talc_config()

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"description\"") |> should.be_false()
  }
}

pub fn generate_no_license_test() {
  let gleam = GleamConfig(..test_gleam_config(), licences: [])
  let talc = test_talc_config()

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"license\"") |> should.be_false()
  }
}

pub fn generate_with_peer_deps_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), peer_dependencies: [
      #("react", ">=18"),
      #("react-dom", ">=18"),
    ])

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"peerDependencies\"") |> should.be_true()
    json |> string_contains("\"react\"") |> should.be_true()
  }
}

pub fn generate_with_extra_fields_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(..test_talc_config(), extra_fields: [
      #("homepage", "https://example.com"),
    ])

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"homepage\"") |> should.be_true()
    json |> string_contains("https://example.com") |> should.be_true()
  }
}

pub fn validate_valid_config_test() {
  let gleam = test_gleam_config()
  package_json.validate(gleam)
  |> should.be_ok()
}

pub fn validate_missing_name_test() {
  let gleam = GleamConfig(..test_gleam_config(), name: "")
  package_json.validate(gleam)
  |> should.be_error()
}

pub fn validate_missing_version_test() {
  let gleam = GleamConfig(..test_gleam_config(), version: "")
  package_json.validate(gleam)
  |> should.be_error()
}

pub fn generate_with_version_override_test() {
  let gleam = test_gleam_config()
  let talc =
    TalcConfig(
      ..test_talc_config(),
      package: PackageConfig(..test_talc_config().package, version: Some("2.0.0-beta.1")),
    )

  package_json.generate(gleam, talc)
  |> should.be_ok()
  |> fn(json: String) {
    json |> string_contains("\"version\":\"2.0.0-beta.1\"") |> should.be_true()
  }
}

pub fn check_report_valid_test() {
  let gleam = test_gleam_config()
  let talc = test_talc_config()

  let report = package_json.check_report(gleam, talc)
  report |> string_contains("✓ Package: my_lib") |> should.be_true()
  report |> string_contains("✓ Version: 1.0.0") |> should.be_true()
}

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
