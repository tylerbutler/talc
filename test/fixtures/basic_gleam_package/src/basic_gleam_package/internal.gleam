@external(javascript, "./greeting.mjs", "greet")
pub fn greet(name: String) -> String {
  "Hi, " <> name <> "!"
}
