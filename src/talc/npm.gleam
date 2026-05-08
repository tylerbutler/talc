/// Functions for invoking npm CLI commands.
///
/// Used by the `pack` and `publish` commands to wrap `npm pack` and
/// `npm publish` with pre-flight checks and flag pass-through.
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Errors from npm operations.
pub type NpmError {
  NpmFailed(command: String, exit_code: Int, output: String)
  NpmTimeout(command: String)
  NpmNotFound
}

/// Internal FFI error discriminants.
type NpmRunError {
  RunTimeout
  RunNotFound
}

/// Errors from publish flag validation.
pub type PublishFlagError {
  InvalidTag(String)
  InvalidAccess(String)
}

/// Formats an NpmError as a human-readable string.
pub fn error_to_string(error: NpmError) -> String {
  case error {
    NpmFailed(cmd, code, output) -> {
      "npm "
      <> cmd
      <> " failed (exit code "
      <> int_to_string(code)
      <> "):\n"
      <> string.trim(output)
    }
    NpmTimeout(cmd) -> "npm " <> cmd <> " timed out"
    NpmNotFound -> "npm executable not found"
  }
}

/// Formats a PublishFlagError as a human-readable string.
pub fn publish_flag_error_to_string(error: PublishFlagError) -> String {
  case error {
    InvalidTag(t) ->
      "Invalid tag \""
      <> t
      <> "\": only alphanumerics, hyphens, underscores, and dots are allowed"
    InvalidAccess(a) ->
      "Invalid access \"" <> a <> "\": must be \"public\" or \"restricted\""
  }
}

/// Runs `npm pack` in the given directory.
pub fn pack(working_dir: String) -> Result(String, NpmError) {
  case run_npm("pack", [], working_dir) {
    Ok(#(0, output)) -> Ok(string.trim(output))
    Ok(#(code, output)) -> Error(NpmFailed("pack", code, output))
    Error(RunNotFound) -> Error(NpmNotFound)
    Error(RunTimeout) -> Error(NpmTimeout("pack"))
  }
}

/// Runs `npm publish` in the given directory with the given flags.
pub fn publish(
  working_dir: String,
  flags: List(String),
) -> Result(String, NpmError) {
  case run_npm("publish", flags, working_dir) {
    Ok(#(0, output)) -> Ok(string.trim(output))
    Ok(#(code, output)) -> Error(NpmFailed("publish", code, output))
    Error(RunNotFound) -> Error(NpmNotFound)
    Error(RunTimeout) -> Error(NpmTimeout("publish"))
  }
}

/// Builds the npm publish flags from optional CLI flag values.
/// Returns an error if any flag value contains unsafe characters.
pub fn build_publish_flags(
  dry_run: Bool,
  tag: Result(String, a),
  access: Result(String, b),
  provenance: Bool,
) -> Result(List(String), PublishFlagError) {
  let tag_result = case tag {
    Error(_) -> Ok(Error(Nil))
    Ok(t) ->
      case is_safe_tag(t) {
        True -> Ok(Ok(t))
        False -> Error(InvalidTag(t))
      }
  }
  let access_result = case access {
    Error(_) -> Ok(Error(Nil))
    Ok("public") -> Ok(Ok("public"))
    Ok("restricted") -> Ok(Ok("restricted"))
    Ok(a) -> Error(InvalidAccess(a))
  }

  case tag_result {
    Error(e) -> Error(e)
    Ok(tag_val) ->
      case access_result {
        Error(e) -> Error(e)
        Ok(access_val) -> {
          let flags = []
          let flags = case dry_run {
            True -> ["--dry-run", ..flags]
            False -> flags
          }
          let flags = case tag_val {
            Ok(t) -> ["--tag", t, ..flags]
            Error(_) -> flags
          }
          let flags = case access_val {
            Ok(a) -> ["--access", a, ..flags]
            Error(_) -> flags
          }
          let flags = case provenance {
            True -> ["--provenance", ..flags]
            False -> flags
          }
          Ok(flags)
        }
      }
  }
}

/// Builds the `--registry <url>` flags for npm publish.
///
/// Returns `["--registry", url]` only when:
/// - registry is `Some(non-empty-url)`, AND
/// - `extra_field_keys` does NOT contain `"publishConfig"`.
///
/// When the user supplies a `publishConfig` via `extra_fields`, their
/// explicit override takes precedence and no `--registry` flag is appended
/// (npm CLI `--registry` would otherwise override `publishConfig.registry`).
///
/// Returns `Error` when the registry URL is an empty string.
pub fn build_registry_flags(
  registry: Option(String),
  extra_field_keys: List(String),
) -> Result(List(String), String) {
  case registry {
    None -> Ok([])
    Some("") -> Error("Registry URL must not be empty")
    Some(url) ->
      case list.contains(extra_field_keys, "publishConfig") {
        True -> Ok([])
        False -> Ok(["--registry", url])
      }
  }
}

fn is_safe_tag(tag: String) -> Bool {
  case tag {
    "" -> False
    _ -> list.all(string.to_graphemes(tag), is_safe_tag_char)
  }
}

fn is_safe_tag_char(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z"
    | "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9"
    | "-"
    | "_"
    | "." -> True
    _ -> False
  }
}

@external(erlang, "talc_npm_ffi", "run_npm")
fn run_npm(
  command: String,
  args: List(String),
  working_dir: String,
) -> Result(#(Int, String), NpmRunError)

import gleam/int

fn int_to_string(n: Int) -> String {
  int.to_string(n)
}
