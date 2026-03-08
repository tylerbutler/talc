/// talc — npm packaging tool for Gleam libraries.
///
/// Reads a compiled Gleam project and produces a publish-ready npm package
/// directory with a generated `package.json`.
import argv
import gleam/io
import gleam/list
import gleam/option
import glint
import talc/gleam_toml
import talc/output
import talc/package_json
import talc/talc_config

pub fn main() {
  glint.new()
  |> glint.with_name("talc")
  |> glint.global_help(
    "npm packaging tool for Gleam libraries.
Generates package.json and assembles npm-ready output from a Gleam project.",
  )
  |> glint.add(at: ["generate"], do: generate_command())
  |> glint.add(at: ["check"], do: check_command())
  |> glint.run(argv.load().arguments)
}

// -- Flags --

const output_dir_flag_name = "output-dir"

fn output_dir_flag() {
  glint.string_flag(output_dir_flag_name)
  |> glint.flag_help("Output directory (default: from talc.toml or npm_dist)")
}

// -- Generate command --

fn generate_command() -> glint.Command(Nil) {
  use output_dir_getter <- glint.flag(output_dir_flag())
  use _named, _unnamed, flags <- glint.command()

  let output_dir_override = case output_dir_getter(flags) {
    Ok(dir) -> option.Some(dir)
    Error(_) -> option.None
  }

  case run_generate(output_dir_override) {
    Ok(files) -> {
      io.println("✓ Generated npm package:")
      list.each(files, fn(f) { io.println("  " <> f) })
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
  output_dir_override: option.Option(String),
) -> Result(List(String), String) {
  use gleam_config <- try_with_message(
    gleam_toml.read(from: "."),
    gleam_config_error_to_string,
  )
  use talc <- try_ok(talc_config.read(from: "."))

  let effective_output_dir = case output_dir_override {
    option.Some(dir) -> dir
    option.None -> talc.package.output_dir
  }

  let effective_talc =
    talc_config.TalcConfig(
      ..talc,
      package: talc_config.PackageConfig(
        ..talc.package,
        output_dir: effective_output_dir,
      ),
    )

  use json_str <- try_with_message(
    package_json.generate(gleam_config, effective_talc),
    generation_error_to_string,
  )

  output.write(effective_output_dir, gleam_config.name, json_str)
  |> map_error(output.error_to_string)
}

fn run_check() -> Result(String, String) {
  use gleam_config <- try_with_message(
    gleam_toml.read(from: "."),
    gleam_config_error_to_string,
  )
  use talc <- try_ok(talc_config.read(from: "."))

  Ok(package_json.check_report(gleam_config, talc))
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
