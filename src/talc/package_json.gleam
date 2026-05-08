/// Generation of `package.json` content from Gleam project metadata.
///
/// This module takes parsed `gleam.toml` and optional `talc.ccl` configuration
/// and produces a well-formed `package.json` string suitable for npm publishing.
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import talc/gleam_toml.{type GleamConfig}
import talc/talc_config.{type TalcConfig}

// Fields that, when all overridden together via extra_fields, mean the
// auto-generated root-module entrypoints will not be emitted at all.
const output_entrypoint_fields = ["exports", "main", "module", "types"]

/// Errors that can occur during package.json generation.
pub type GenerationError {
  /// The package root module (matching gleam.toml `name`) was not found in the
  /// provided module list. This means the JavaScript build output is missing the
  /// root module file that the root export would point to.
  MissingRootModule(String)
}

/// Returns True when `talc_config.extra_fields` overrides every field that
/// the generator would derive from the root module (`exports`, `main`,
/// `module`, and `types`).  When all four are overridden the auto-generated
/// root entrypoint paths are unused, so a missing root module is harmless.
pub fn has_full_output_overrides(talc_config: TalcConfig) -> Bool {
  let extra_keys =
    talc_config.extra_fields
    |> list.map(fn(pair) { pair.0 })
  list.all(output_entrypoint_fields, fn(key) { list.contains(extra_keys, key) })
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
///
/// When `use_true_myth` is enabled in config, exports point at wrapper
/// modules and true-myth is added as a peer dependency.
/// `wrapped_modules` is the set of module names that have wrapper files.
pub fn generate_with_modules(
  gleam_config: GleamConfig,
  talc_config: TalcConfig,
  module_names: List(String),
  wrapped_modules: Set(String),
) -> Result(String, GenerationError) {
  // When a module list is provided, require the root module to be present —
  // unless extra_fields fully overrides all auto-generated entrypoint fields,
  // in which case the root-module paths are never emitted.
  case module_names {
    [] -> Ok(Nil)
    _ ->
      case
        has_full_output_overrides(talc_config)
        || list.contains(module_names, gleam_config.name)
      {
        True -> Ok(Nil)
        False -> Error(MissingRootModule(gleam_config.name))
      }
  }
  |> result.try(fn(_) {
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

    let esm_fields =
      build_esm_fields(
        gleam_config.name,
        module_names,
        talc_config.use_true_myth,
        wrapped_modules,
      )
    let repository_fields = build_repository_fields(gleam_config)
    let extra_fields = build_extra_fields(talc_config)
    let publish_config_fields = build_publish_config_fields(talc_config)
    let peer_dep_fields =
      build_peer_dep_fields(
        talc_config,
        talc_config.use_true_myth,
        wrapped_modules,
      )

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
        publish_config_fields,
        peer_dep_fields,
      ])
      |> list.filter(fn(pair) { !dict.has_key(extra_keys, pair.0) })

    let all_fields = list.flatten([auto_fields, extra_fields])

    Ok(json.to_string(json.object(all_fields)))
  })
}

/// Builds the npm package name, optionally with a scope prefix.
fn build_npm_name(name: String, config: TalcConfig) -> String {
  case config.package.scope {
    Some(scope) -> scope <> "/" <> name
    None -> name
  }
}

/// Builds ESM module entry point fields with sub-path exports.
///
/// When `use_true_myth` is true and a module has wrapper files,
/// exports point at the wrapper; otherwise they point at native Gleam output.
fn build_esm_fields(
  package_name: String,
  module_names: List(String),
  use_true_myth: Bool,
  wrapped_modules: Set(String),
) -> List(#(String, json.Json)) {
  let #(main_path, types_path) =
    module_paths(package_name, package_name, use_true_myth, wrapped_modules)

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
      let #(mjs_path, dts_path) =
        module_paths(module_name, package_name, use_true_myth, wrapped_modules)
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

/// Returns the (mjs_path, types_path) for a module based on wrapper mode.
fn module_paths(
  module_name: String,
  _package_name: String,
  use_true_myth: Bool,
  wrapped_modules: Set(String),
) -> #(String, String) {
  case use_true_myth && set.contains(wrapped_modules, module_name) {
    True -> #(
      "./dist/_wrapper/" <> module_name <> ".mjs",
      "./dist/_wrapper/" <> module_name <> ".d.ts",
    )
    False -> #(
      "./dist/" <> module_name <> ".mjs",
      "./dist/" <> module_name <> ".d.mts",
    )
  }
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

/// Builds publishConfig field from talc.ccl registry config.
/// When registry is set, adds publishConfig.registry to direct npm publish
/// to the configured registry.
fn build_publish_config_fields(
  config: TalcConfig,
) -> List(#(String, json.Json)) {
  case config.package.registry {
    None -> []
    Some(url) -> [
      #("publishConfig", json.object([#("registry", json.string(url))])),
    ]
  }
}

/// Builds extra package.json fields from talc.ccl overrides.
fn build_extra_fields(config: TalcConfig) -> List(#(String, json.Json)) {
  config.extra_fields
}

/// Builds peerDependencies field from talc.ccl config.
/// When true-myth wrappers are enabled and any modules were wrapped,
/// true-myth is automatically added as a peer dependency.
fn build_peer_dep_fields(
  config: TalcConfig,
  use_true_myth: Bool,
  wrapped_modules: Set(String),
) -> List(#(String, json.Json)) {
  let explicit_keys =
    config.peer_dependencies
    |> list.map(fn(pair) { pair.0 })
    |> set.from_list()

  // Auto-add true-myth when enabled and wrappers were generated
  let auto_deps = case
    use_true_myth
    && set.size(wrapped_modules) > 0
    && !set.contains(explicit_keys, "true-myth")
  {
    True -> [#("true-myth", ">=8.0.0")]
    False -> []
  }

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
  check_report_with_modules(gleam_config, talc_config, [], set.new())
}

/// Generates a pretty-printed validation report using the given module list.
///
/// Passes `module_names` to `generate_with_modules` so that root-module
/// validation is performed the same way `generate` would perform it at
/// actual package generation time.
pub fn check_report_with_modules(
  gleam_config: GleamConfig,
  talc_config: TalcConfig,
  module_names: List(String),
  wrapped_modules: Set(String),
) -> String {
  let validation = validate(gleam_config)
  let generation =
    generate_with_modules(
      gleam_config,
      talc_config,
      module_names,
      wrapped_modules,
    )

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
