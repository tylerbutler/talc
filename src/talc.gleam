/// talc — npm packaging tool for Gleam libraries.
///
/// Reads a compiled Gleam project and produces a publish-ready npm package
/// directory with a generated `package.json` and `.d.ts` type declarations.
import argv
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import glint
import talc/dts
import talc/gleam_toml
import talc/interface
import talc/output
import talc/package_json
import talc/talc_config

pub fn main() {
  glint.new()
  |> glint.with_name("talc")
  |> glint.global_help(
    "npm packaging tool for Gleam libraries.
Generates package.json, .d.ts declarations, and assembles npm-ready output from a Gleam project.",
  )
  |> glint.add(at: ["generate"], do: generate_command())
  |> glint.add(at: ["check"], do: check_command())
  |> glint.run(argv.load().arguments)
}

// -- Flags --

fn output_dir_flag() {
  glint.string_flag("output-dir")
  |> glint.flag_help("Output directory (default: from talc.toml or npm_dist)")
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

  // Load package interface for type generation and module filtering
  use package <- try_ok(interface.load())

  let module_names = interface.public_module_names(package)

  // Generate package.json with sub-path exports
  use json_str <- try_with_message(
    package_json.generate_with_modules(
      gleam_config,
      effective_talc,
      module_names,
    ),
    generation_error_to_string,
  )

  // Generate .d.ts files for each module
  let #(dts_files, all_warnings) =
    dict.to_list(package.modules)
    |> list.fold(#([], []), fn(acc, pair) {
      let #(files, warnings) = acc
      let #(module_name, module) = pair
      let result = dts.emit_module(module, package.name)
      let dts_path = interface.module_to_dts_path(module_name)
      #(
        list.append(files, [#(dts_path, result.content)]),
        list.append(warnings, result.warnings),
      )
    })

  // Write output
  use written <- try_ok(
    output.write(
      effective_output_dir,
      gleam_config.name,
      json_str,
      Some(module_names),
      dts_files,
    )
    |> map_error(output.error_to_string),
  )

  Ok(#(written, all_warnings))
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

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
