/// Returns a greeting string.
pub fn greet(name: String) -> String {
  "Hello, " <> name <> "!"
}

/// Returns a Result so talc generates a true-myth wrapper.
pub fn parse_ready() -> Result(Int, String) {
  Ok(42)
}
