/// Functions for invoking npm CLI commands.
///
/// Used by the `pack` and `publish` commands to wrap `npm pack` and
/// `npm publish` with pre-flight checks and flag pass-through.
import gleam/string

/// Result of running an npm command.
pub type NpmResult {
  NpmResult(exit_code: Int, output: String)
}

/// Errors from npm operations.
pub type NpmError {
  NpmFailed(command: String, exit_code: Int, output: String)
  NpmTimeout(command: String)
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
  }
}

/// Runs `npm pack` in the given directory.
pub fn pack(working_dir: String) -> Result(String, NpmError) {
  case run_npm("pack", working_dir) {
    Ok(#(0, output)) -> Ok(string.trim(output))
    Ok(#(code, output)) -> Error(NpmFailed("pack", code, output))
    Error(Nil) -> Error(NpmTimeout("pack"))
  }
}

/// Runs `npm publish` in the given directory with the given flags.
pub fn publish(
  working_dir: String,
  flags: List(String),
) -> Result(String, NpmError) {
  let args = case flags {
    [] -> "publish"
    _ -> "publish " <> string.join(flags, " ")
  }
  case run_npm(args, working_dir) {
    Ok(#(0, output)) -> Ok(string.trim(output))
    Ok(#(code, output)) -> Error(NpmFailed("publish", code, output))
    Error(Nil) -> Error(NpmTimeout("publish"))
  }
}

/// Builds the npm publish flags from optional CLI flag values.
pub fn build_publish_flags(
  dry_run: Bool,
  tag: Result(String, a),
  access: Result(String, b),
  provenance: Bool,
) -> List(String) {
  let flags = []
  let flags = case dry_run {
    True -> ["--dry-run", ..flags]
    False -> flags
  }
  let flags = case tag {
    Ok(t) -> ["--tag", t, ..flags]
    Error(_) -> flags
  }
  let flags = case access {
    Ok(a) -> ["--access", a, ..flags]
    Error(_) -> flags
  }
  let flags = case provenance {
    True -> ["--provenance", ..flags]
    False -> flags
  }
  flags
}

@external(erlang, "talc_npm_ffi", "run_npm")
fn run_npm(args: String, working_dir: String) -> Result(#(Int, String), Nil)

import gleam/int

fn int_to_string(n: Int) -> String {
  int.to_string(n)
}
