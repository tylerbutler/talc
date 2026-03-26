/// talc — npm packaging tool for Gleam libraries.
///
/// Reads a compiled Gleam project and produces a publish-ready npm package
/// directory with Gleam's native `.d.mts` type declarations and optional
/// true-myth wrapper modules for Result/Option types.
import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import glint
import simplifile
import talc/gleam_toml
import talc/interface
import talc/npm
import talc/output
import talc/package_json
import talc/talc_config
import talc/wrapper

pub fn main() {
  glint.new()
  |> glint.with_name("talc")
  |> glint.global_help(
    "npm packaging tool for Gleam libraries.
Copies Gleam's native .d.mts declarations and assembles npm-ready output from a Gleam project.",
  )
  |> glint.add(at: ["generate"], do: generate_command())
  |> glint.add(at: ["check"], do: check_command())
  |> glint.add(at: ["pack"], do: pack_command())
  |> glint.add(at: ["publish"], do: publish_command())
  |> glint.run(argv.load().arguments)
}

// -- Flags --

fn output_dir_flag() {
  glint.string_flag("output-dir")
  |> glint.flag_help("Output directory (default: from talc.ccl or npm_dist)")
}

fn dry_run_flag() {
  glint.bool_flag("dry-run")
  |> glint.flag_help("Perform a dry run without actually publishing")
}

fn tag_flag() {
  glint.string_flag("tag")
  |> glint.flag_help("npm dist-tag to publish under (default: latest)")
}

fn access_flag() {
  glint.string_flag("access")
  |> glint.flag_help("Package access level: public or restricted")
}

fn provenance_flag() {
  glint.bool_flag("provenance")
  |> glint.flag_help("Generate provenance attestation (CI only)")
}

// -- Generate command --

fn generate_command() -> glint.Command(Nil) {
  use output_dir_getter <- glint.flag(output_dir_flag())
  use _named, _unnamed, flags <- glint.command()

  let output_dir_override = case output_dir_getter(flags) {
    Ok(dir) -> Some(dir)
    Error(_) -> None
  }

  case run_generate(output_dir_override) {
    Ok(#(files, warnings)) -> {
      io.println("✓ Generated npm package:")
      list.each(files, fn(f) { io.println("  " <> f) })
      print_warnings(warnings)
    }
    Error(msg) -> {
      io.println_error("✗ " <> msg)
      halt(1)
    }
  }
}

// -- Check command --

fn check_command() -> glint.Command(Nil) {
  use _named, _unnamed, _flags <- glint.command()

  case run_check() {
    Ok(report) -> io.println(report)
    Error(msg) -> {
      io.println_error("✗ " <> msg)
      halt(1)
    }
  }
}

// -- Pack command --

fn pack_command() -> glint.Command(Nil) {
  use output_dir_getter <- glint.flag(output_dir_flag())
  use _named, _unnamed, flags <- glint.command()

  let output_dir_override = case output_dir_getter(flags) {
    Ok(dir) -> Some(dir)
    Error(_) -> None
  }

  case run_pack(output_dir_override) {
    Ok(#(tarball, warnings)) -> {
      io.println("✓ Packed: " <> tarball)
      print_warnings(warnings)
    }
    Error(msg) -> {
      io.println_error("✗ " <> msg)
      halt(1)
    }
  }
}

// -- Publish command --

fn publish_command() -> glint.Command(Nil) {
  use output_dir_getter <- glint.flag(output_dir_flag())
  use dry_run_getter <- glint.flag(dry_run_flag())
  use tag_getter <- glint.flag(tag_flag())
  use access_getter <- glint.flag(access_flag())
  use provenance_getter <- glint.flag(provenance_flag())
  use _named, _unnamed, flags <- glint.command()

  let output_dir_override = case output_dir_getter(flags) {
    Ok(dir) -> Some(dir)
    Error(_) -> None
  }

  let publish_flags =
    npm.build_publish_flags(
      result.unwrap(dry_run_getter(flags), False),
      tag_getter(flags),
      access_getter(flags),
      result.unwrap(provenance_getter(flags), False),
    )

  case run_publish(output_dir_override, publish_flags) {
    Ok(#(npm_output, warnings)) -> {
      io.println("✓ Published!")
      case npm_output {
        "" -> Nil
        out -> io.println(out)
      }
      print_warnings(warnings)
    }
    Error(msg) -> {
      io.println_error("✗ " <> msg)
      halt(1)
    }
  }
}

// -- Core logic --

fn run_generate(
  output_dir_override: Option(String),
) -> Result(#(List(String), List(String)), String) {
  use gleam_config <- try_with_message(
    gleam_toml.read(from: "."),
    gleam_config_error_to_string,
  )
  use talc <- try_ok(talc_config.read(from: "."))

  let effective_output_dir = case output_dir_override {
    Some(dir) -> dir
    None -> talc.package.output_dir
  }

  let effective_talc =
    talc_config.TalcConfig(
      ..talc,
      package: talc_config.PackageConfig(
        ..talc.package,
        output_dir: effective_output_dir,
      ),
    )

  // Load package interface for module discovery and function signatures
  use package <- try_ok(interface.load())

  let module_names = interface.public_module_names(package)

  let available_type_files =
    scan_type_declarations(effective_talc.type_declarations_dir)

  // Generate wrapper files if use_true_myth is enabled
  let #(generated_files, wrapped_modules, all_warnings, all_resolved_types) = case
    effective_talc.use_true_myth
  {
    True -> {
      dict.to_list(package.modules)
      |> list.fold(#([], set.new(), [], set.new()), fn(acc, pair) {
        let #(files, wrapped, warnings, resolved_types) = acc
        let #(module_name, module) = pair
        let result =
          wrapper.generate_module_wrapper(
            module,
            module_name,
            available_type_files,
          )
        let new_resolved =
          set.union(resolved_types, result.resolved_type_files)
        case result.has_wrapped_functions {
          True -> {
            let wrapper_mjs_path = "_wrapper/" <> module_name <> ".mjs"
            let wrapper_dts_path = "_wrapper/" <> module_name <> ".d.ts"
            #(
              list.append(files, [
                #(wrapper_mjs_path, result.mjs),
                #(wrapper_dts_path, result.dts),
              ]),
              set.insert(wrapped, module_name),
              list.append(warnings, result.warnings),
              new_resolved,
            )
          }
          False ->
            #(
              files,
              wrapped,
              list.append(warnings, result.warnings),
              new_resolved,
            )
        }
      })
    }
    False -> #([], set.new(), [], set.new())
  }

  // Generate package.json with sub-path exports
  use json_str <- try_with_message(
    package_json.generate_with_modules(
      gleam_config,
      effective_talc,
      module_names,
      wrapped_modules,
    ),
    generation_error_to_string,
  )

  // Write output
  use written <- try_ok(
    output.write(
      effective_output_dir,
      gleam_config.name,
      json_str,
      Some(module_names),
      generated_files,
    )
    |> map_error(output.error_to_string),
  )

  // Copy referenced type declaration files to output
  use type_files <- try_ok(
    output.copy_type_declarations(
      effective_talc.type_declarations_dir,
      effective_output_dir,
      all_resolved_types,
    )
    |> map_error(output.error_to_string),
  )

  Ok(#(list.append(written, type_files), all_warnings))
}

fn run_pack(
  output_dir_override: Option(String),
) -> Result(#(String, List(String)), String) {
  use #(_files, warnings) <- try_ok(run_generate(output_dir_override))

  let output_dir = resolve_output_dir(output_dir_override)

  use tarball <- try_ok(npm.pack(output_dir) |> map_error(npm.error_to_string))

  Ok(#(tarball, warnings))
}

fn run_publish(
  output_dir_override: Option(String),
  flags: List(String),
) -> Result(#(String, List(String)), String) {
  use #(_files, warnings) <- try_ok(run_generate(output_dir_override))

  let output_dir = resolve_output_dir(output_dir_override)

  use npm_output <- try_ok(
    npm.publish(output_dir, flags) |> map_error(npm.error_to_string),
  )

  Ok(#(npm_output, warnings))
}

/// Resolves the effective output directory from optional override and config.
fn resolve_output_dir(override: Option(String)) -> String {
  case override {
    Some(dir) -> dir
    None ->
      case talc_config.read(from: ".") {
        Ok(talc) -> talc.package.output_dir
        Error(_) -> "npm_dist"
      }
  }
}

fn run_check() -> Result(String, String) {
  use gleam_config <- try_with_message(
    gleam_toml.read(from: "."),
    gleam_config_error_to_string,
  )
  use talc <- try_ok(talc_config.read(from: "."))

  // Try to load package interface for richer check output
  let interface_info = case interface.load() {
    Ok(package) -> {
      let module_count = list.length(interface.public_module_names(package))
      "\n✓ Package interface: "
      <> int.to_string(module_count)
      <> " public module(s)"
    }
    Error(_) -> "\n⚠ Package interface not available (run `gleam build` first)"
  }

  Ok(package_json.check_report(gleam_config, talc) <> interface_info)
}

fn print_warnings(warnings: List(String)) {
  case warnings {
    [] -> Nil
    _ -> {
      io.println_error(
        "\n⚠ " <> int.to_string(list.length(warnings)) <> " warning(s):",
      )
      list.each(warnings, fn(w) { io.println_error("  " <> w) })
    }
  }
}

// -- Error formatting --

fn gleam_config_error_to_string(error: gleam_toml.ConfigError) -> String {
  case error {
    gleam_toml.FileError(msg) -> msg
    gleam_toml.ParseError(msg) -> "gleam.toml parse error: " <> msg
    gleam_toml.MissingField(field) ->
      "gleam.toml missing required field: " <> field
  }
}

fn generation_error_to_string(error: package_json.GenerationError) -> String {
  case error {
    package_json.MissingName -> "Package name is required"
    package_json.MissingVersion -> "Package version is required"
  }
}

// -- Helpers --

fn try_ok(
  result: Result(a, String),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> next(value)
    Error(msg) -> Error(msg)
  }
}

fn try_with_message(
  result: Result(a, e),
  to_string: fn(e) -> String,
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(to_string(err))
  }
}

fn map_error(result: Result(a, e), f: fn(e) -> String) -> Result(a, String) {
  case result {
    Ok(value) -> Ok(value)
    Error(err) -> Error(f(err))
  }
}

/// Scans the type declarations directory and returns a set of
/// available #(package, module) pairs based on .d.ts file existence.
fn scan_type_declarations(dir: String) -> set.Set(#(String, String)) {
  case simplifile.is_directory(dir) {
    Ok(True) -> scan_type_dir_recursive(dir, dir)
    _ -> set.new()
  }
}

fn scan_type_dir_recursive(
  base_dir: String,
  current_dir: String,
) -> set.Set(#(String, String)) {
  case simplifile.read_directory(current_dir) {
    Ok(entries) ->
      list.fold(entries, set.new(), fn(acc, entry) {
        let path = current_dir <> "/" <> entry
        case simplifile.is_directory(path) {
          Ok(True) ->
            set.union(acc, scan_type_dir_recursive(base_dir, path))
          _ ->
            case string.ends_with(entry, ".d.ts") {
              True -> {
                let rel =
                  string.drop_start(path, string.length(base_dir) + 1)
                let module_path =
                  string.drop_end(rel, string.length(".d.ts"))
                case string.split(module_path, "/") {
                  [package, ..module_parts] ->
                    set.insert(acc, #(
                      package,
                      string.join(module_parts, "/"),
                    ))
                  _ -> acc
                }
              }
              False -> acc
            }
        }
      })
    Error(_) -> set.new()
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
