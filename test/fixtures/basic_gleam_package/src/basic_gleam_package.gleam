import gleam/int
import gleam/option.{type Option, None, Some}

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

pub type Person {
  Person(name: String)
}

/// Reads a field from a native custom type.
pub fn person_name(person: Person) -> String {
  person.name
}

/// Converts a result parameter into an option.
pub fn result_to_option(value: Result(Int, String)) -> Option(Int) {
  case value {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

/// Calls a private module that uses a local JavaScript external.
@external(javascript, "./basic_gleam_package/internal.mjs", "greet")
pub fn external_greeting(name: String) -> String {
  "Hi, " <> name <> "!"
}

/// Calls a local external with a .js extension.
@external(javascript, "./identity.js", "identity")
pub fn identity(value: Int) -> Int {
  value
}
