/// Generation of `package.json` content from Gleam project metadata.
///
/// This module takes parsed `gleam.toml` and optional `talc.ccl` configuration
/// and produces a well-formed `package.json` string suitable for npm publishing.
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string
import talc/gleam_toml.{type GleamConfig}
import talc/talc_config.{type TalcConfig}

/// Errors that can occur during package.json generation.
pub type GenerationError {
  MissingName
  MissingVersion
}

/// Generates a package.json JSON string from Gleam and talc configs.
///
/// When `module_names` is provided, sub-path exports are generated
/// for each public module.
pub fn generate(
  gleam_config: GleamConfig,
  talc_config: TalcConfig,
) -> Result(String, GenerationError) {
  generate_with_modules(gleam_config, talc_config, [], set.new())
}

/// Generates package.json with sub-path exports for the given modules.
pub fn generate_with_modules(
  gleam_config: GleamConfig,
  talc_config: TalcConfig,
  module_names: List(String),
  used_type_map_packages: Set(String),
) -> Result(String, GenerationError) {
  let npm_name = build_npm_name(gleam_config.name, talc_config)

  let base_fields = [
    #("name", json.string(npm_name)),
    #("version", json.string(gleam_config.version)),
    #("type", json.string("module")),
  ]

  let description_fields = case gleam_config.description {
    "" -> []
    desc -> [#("description", json.string(desc))]
  }

  let license_fields = case gleam_config.licences {
    [first, ..] -> [#("license", json.string(first))]
    [] -> []
  }

  let esm_fields = build_esm_fields(gleam_config.name, module_names)
  let repository_fields = build_repository_fields(gleam_config)
  let extra_fields = build_extra_fields(talc_config)
  let peer_dep_fields =
    build_peer_dep_fields(talc_config, used_type_map_packages)

  // Extra fields from [package.json] override auto-generated fields
  let extra_keys =
    extra_fields
    |> list.map(fn(pair) { #(pair.0, Nil) })
    |> dict.from_list()

  let auto_fields =
    list.flatten([
      base_fields,
      description_fields,
      license_fields,
      esm_fields,
      repository_fields,
      peer_dep_fields,
    ])
    |> list.filter(fn(pair) { !dict.has_key(extra_keys, pair.0) })

  let all_fields = list.flatten([auto_fields, extra_fields])

  Ok(json.to_string(json.object(all_fields)))
}

/// Builds the npm package name, optionally with a scope prefix.
fn build_npm_name(name: String, config: TalcConfig) -> String {
  case config.package.scope {
    Some(scope) -> scope <> "/" <> name
    None -> name
  }
}

/// Builds ESM module entry point fields with sub-path exports.
fn build_esm_fields(
  package_name: String,
  module_names: List(String),
) -> List(#(String, json.Json)) {
  let main_path = "./dist/" <> package_name <> ".mjs"
  let types_path = "./dist/" <> package_name <> ".d.ts"

  let root_export = #(
    ".",
    json.object([
      #("import", json.string(main_path)),
      #("types", json.string(types_path)),
    ]),
  )

  // Build sub-path exports for non-root public modules
  let sub_exports =
    module_names
    |> list.filter(fn(m) { m != package_name })
    |> list.sort(string.compare)
    |> list.map(fn(module_name) {
      let sub_path =
        "./"
        <> string.replace(strip_prefix(module_name, package_name), "/", "/")
      let mjs_path = "./dist/" <> module_name <> ".mjs"
      let dts_path = "./dist/" <> module_name <> ".d.ts"
      #(
        sub_path,
        json.object([
          #("import", json.string(mjs_path)),
          #("types", json.string(dts_path)),
        ]),
      )
    })

  let exports = json.object([root_export, ..sub_exports])

  [
    #("main", json.string(main_path)),
    #("module", json.string(main_path)),
    #("types", json.string(types_path)),
    #("exports", exports),
  ]
}

/// Strips the package name prefix from a module name.
/// "birch/handler" with prefix "birch" → "handler"
fn strip_prefix(module_name: String, prefix: String) -> String {
  case string.starts_with(module_name, prefix <> "/") {
    True -> string.drop_start(module_name, string.length(prefix) + 1)
    False -> module_name
  }
}

/// Builds repository field from gleam.toml repository config.
fn build_repository_fields(config: GleamConfig) -> List(#(String, json.Json)) {
  case config.repository {
    Ok(repo) -> {
      let url = repository_url(repo)
      [
        #(
          "repository",
          json.object([
            #("type", json.string("git")),
            #("url", json.string(url)),
          ]),
        ),
      ]
    }
    Error(_) -> []
  }
}

/// Converts a Repository to a git URL.
fn repository_url(repo: gleam_toml.Repository) -> String {
  case repo.type_ {
    "github" -> "https://github.com/" <> repo.user <> "/" <> repo.repo
    "gitlab" -> "https://gitlab.com/" <> repo.user <> "/" <> repo.repo
    "bitbucket" -> "https://bitbucket.org/" <> repo.user <> "/" <> repo.repo
    _ -> repo.user <> "/" <> repo.repo
  }
}

/// Builds extra package.json fields from talc.ccl overrides.
fn build_extra_fields(config: TalcConfig) -> List(#(String, json.Json)) {
  config.extra_fields
}

/// Builds peerDependencies field from talc.ccl and used type-mapped packages.
/// Explicitly configured peer dependencies take precedence over auto-added ones.
fn build_peer_dep_fields(
  config: TalcConfig,
  used_type_map_packages: Set(String),
) -> List(#(String, json.Json)) {
  // Start with explicit peer dependencies
  let explicit_keys =
    config.peer_dependencies
    |> list.map(fn(pair) { pair.0 })
    |> set.from_list()

  // Add type-mapped packages that aren't already explicitly declared
  let auto_deps =
    set.to_list(used_type_map_packages)
    |> list.filter(fn(pkg) { !set.contains(explicit_keys, pkg) })
    |> list.sort(string.compare)
    |> list.map(fn(pkg) { #(pkg, "*") })

  let all_deps = list.append(config.peer_dependencies, auto_deps)

  case all_deps {
    [] -> []
    deps -> {
      let dep_object =
        deps
        |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
        |> json.object()
      [#("peerDependencies", dep_object)]
    }
  }
}

/// Validates that the generated config has all required fields.
pub fn validate(gleam_config: GleamConfig) -> Result(Nil, List(String)) {
  let errors =
    []
    |> check_non_empty(gleam_config.name, "name")
    |> check_non_empty(gleam_config.version, "version")

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

fn check_non_empty(
  errors: List(String),
  value: String,
  field: String,
) -> List(String) {
  case value {
    "" -> list.append(errors, ["Missing required field: " <> field])
    _ -> errors
  }
}

/// Generates a pretty-printed validation report.
pub fn check_report(
  gleam_config: GleamConfig,
  talc_config: TalcConfig,
) -> String {
  let validation = validate(gleam_config)
  let generation = generate(gleam_config, talc_config)

  case validation, generation {
    Ok(_), Ok(json_str) -> {
      let npm_name = build_npm_name(gleam_config.name, talc_config)
      "✓ Package: "
      <> npm_name
      <> "\n"
      <> "✓ Version: "
      <> gleam_config.version
      <> "\n"
      <> "✓ package.json is valid ("
      <> int.to_string(string.byte_size(json_str))
      <> " bytes)\n"
      <> "✓ Output directory: "
      <> talc_config.package.output_dir
    }
    Error(errors), _ -> {
      "Validation failed:\n"
      <> string.join(list.map(errors, fn(e) { "  ✗ " <> e }), "\n")
    }
    _, Error(_) -> "Failed to generate package.json"
  }
}
