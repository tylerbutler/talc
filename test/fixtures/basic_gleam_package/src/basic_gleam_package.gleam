import gleam/int

@external(javascript, "./thing.d.mts", "Thing")
pub type Thing(a)

/// Returns a greeting string.
pub fn greet(name: String) -> String {
  "Hello, " <> name <> "!"
}

/// Parses a positive integer from a string.
/// Returns Ok(n) if positive, or Error(msg) otherwise.
pub fn parse_positive(s: String) -> Result(Int, String) {
  case int.parse(s) {
    Ok(n) if n > 0 -> Ok(n)
    Ok(_) -> Error("not positive")
    Error(_) -> Error("not a number")
  }
}

/// Returns the provided external Thing value in an Ok result.
pub fn keep_thing(thing: Thing(Int)) -> Result(Thing(Int), String) {
  Ok(thing)
}
