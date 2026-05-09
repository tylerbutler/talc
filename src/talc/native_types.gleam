/// Parser for Gleam's generated JavaScript `.d.mts` declarations.
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import simplifile

/// A native TypeScript import line from a generated declaration file.
pub type NativeImport {
  NativeImport(line: String, specifier: String)
}

/// A native TypeScript function signature from a generated declaration file.
pub type NativeFunctionSignature {
  NativeFunctionSignature(
    parameters: List(#(String, String)),
    return_type: String,
  )
}

/// Native TypeScript types parsed for one Gleam module declaration file.
pub type NativeModuleTypes {
  NativeModuleTypes(
    imports: List(NativeImport),
    functions: Dict(String, NativeFunctionSignature),
  )
}

/// Errors that can occur while reading native declaration files.
pub type NativeTypeError {
  ReadError(path: String, detail: String)
}

type ParsedLine {
  ParsedImport(NativeImport)
  ParsedFunction(String, NativeFunctionSignature)
  ParsedNothing
}

type SplitState {
  SplitState(
    current: List(String),
    parts: List(String),
    angle_depth: Int,
    square_depth: Int,
    paren_depth: Int,
  )
}

type ExtractState {
  ExtractState(
    current: List(String),
    rest: List(String),
    depth: Int,
    done: Bool,
  )
}

type LogicalLineState {
  LogicalLineState(lines: List(String), current_function: List(String))
}

/// Parses `.d.mts` content into imports and function signatures.
pub fn parse(content: String) -> NativeModuleTypes {
  content
  |> string.split("\n")
  |> list.map(string.trim)
  |> combine_logical_lines
  |> list.fold(
    NativeModuleTypes(imports: [], functions: dict.new()),
    fn(module, line) {
      case parse_line(line) {
        ParsedImport(import_) ->
          NativeModuleTypes(..module, imports: [import_, ..module.imports])
        ParsedFunction(name, signature) ->
          NativeModuleTypes(
            ..module,
            functions: dict.insert(module.functions, name, signature),
          )
        ParsedNothing -> module
      }
    },
  )
  |> reverse_imports
}

fn combine_logical_lines(lines: List(String)) -> List(String) {
  lines
  |> list.fold(
    LogicalLineState(lines: [], current_function: []),
    combine_logical_line,
  )
  |> finish_logical_lines
}

fn combine_logical_line(
  state: LogicalLineState,
  line: String,
) -> LogicalLineState {
  case state.current_function {
    [] -> {
      case
        string.starts_with(line, "export function ")
        && !string.ends_with(line, ";")
      {
        True -> LogicalLineState(..state, current_function: [line])
        False -> LogicalLineState(..state, lines: [line, ..state.lines])
      }
    }
    current -> {
      let current = [line, ..current]
      case string.ends_with(line, ";") {
        True ->
          LogicalLineState(
            lines: [join_logical_line(current), ..state.lines],
            current_function: [],
          )
        False -> LogicalLineState(..state, current_function: current)
      }
    }
  }
}

fn finish_logical_lines(state: LogicalLineState) -> List(String) {
  let lines = case state.current_function {
    [] -> state.lines
    current -> [join_logical_line(current), ..state.lines]
  }

  list.reverse(lines)
}

fn join_logical_line(reversed_lines: List(String)) -> String {
  reversed_lines
  |> list.reverse
  |> string.join(" ")
}

/// Reads and parses `build/dev/javascript/<package>/<module>.d.mts`.
pub fn read_module(
  package_name: String,
  module_name: String,
) -> Result(NativeModuleTypes, NativeTypeError) {
  let path =
    "build/dev/javascript/" <> package_name <> "/" <> module_name <> ".d.mts"

  case simplifile.read(path) {
    Ok(content) -> Ok(parse(content))
    Error(error) ->
      Error(ReadError(path: path, detail: file_error_to_string(error)))
  }
}

/// Splits a string on a delimiter only when outside nested generics, tuples,
/// arrays, and function parameter lists.
pub fn split_balanced(input: String, delimiter: String) -> List(String) {
  let state =
    input
    |> string.to_graphemes
    |> list.fold(
      SplitState(
        current: [],
        parts: [],
        angle_depth: 0,
        square_depth: 0,
        paren_depth: 0,
      ),
      fn(state, grapheme) { split_step(state, grapheme, delimiter) },
    )

  finish_split(state)
}

fn reverse_imports(module: NativeModuleTypes) -> NativeModuleTypes {
  NativeModuleTypes(..module, imports: list.reverse(module.imports))
}

fn parse_line(line: String) -> ParsedLine {
  case string.starts_with(line, "import type ") {
    True -> parse_import(line)
    False -> parse_function(line)
  }
}

fn parse_import(line: String) -> ParsedLine {
  case string.split_once(line, " from \"") {
    Ok(#(_before, after_from)) ->
      case string.split_once(after_from, "\"") {
        Ok(#(specifier, _after)) ->
          ParsedImport(NativeImport(line: line, specifier: specifier))
        Error(_) -> ParsedNothing
      }
    Error(_) -> ParsedNothing
  }
}

fn parse_function(line: String) -> ParsedLine {
  case string.starts_with(line, "export function ") {
    False -> ParsedNothing
    True -> {
      let rest = string.drop_start(line, string.length("export function "))
      case string.split_once(rest, "(") {
        Ok(#(name, after_name)) -> {
          let #(parameters, after_parameters) =
            extract_balanced(after_name, "(", ")")
          case string.split_once(after_parameters, ":") {
            Ok(#(_before_return, return_and_semicolon)) -> {
              let return_type =
                return_and_semicolon
                |> string.trim
                |> strip_trailing_semicolon
              case parse_parameters(parameters) {
                Ok(parameters) ->
                  ParsedFunction(
                    parse_function_name(name),
                    NativeFunctionSignature(
                      parameters: parameters,
                      return_type: return_type,
                    ),
                  )
                Error(_) -> ParsedNothing
              }
            }
            Error(_) -> ParsedNothing
          }
        }
        Error(_) -> ParsedNothing
      }
    }
  }
}

fn parse_function_name(name: String) -> String {
  let name = string.trim(name)
  case string.split_once(name, "<") {
    Ok(#(base_name, _generics)) -> string.trim(base_name)
    Error(_) -> name
  }
}

fn parse_parameters(
  parameters: String,
) -> Result(List(#(String, String)), Nil) {
  parameters
  |> split_balanced(",")
  |> list.fold(Ok([]), fn(parsed, parameter) {
    let parameter = string.trim(parameter)
    case parsed, parameter {
      Error(_), _ -> Error(Nil)
      Ok(parameters), "" -> Ok(parameters)
      Ok(parameters), _ ->
        case parse_parameter(parameter) {
          Ok(parameter) -> Ok([parameter, ..parameters])
          Error(_) -> Error(Nil)
        }
    }
  })
  |> reverse_parameters
}

fn reverse_parameters(
  parameters: Result(List(#(String, String)), Nil),
) -> Result(List(#(String, String)), Nil) {
  case parameters {
    Ok(parameters) -> Ok(list.reverse(parameters))
    Error(_) -> Error(Nil)
  }
}

fn parse_parameter(parameter: String) -> Result(#(String, String), Nil) {
  case split_top_level_once(parameter, ":") {
    Ok(#(name, type_)) -> Ok(#(string.trim(name), string.trim(type_)))
    Error(_) -> Error(Nil)
  }
}

fn split_top_level_once(
  input: String,
  delimiter: String,
) -> Result(#(String, String), Nil) {
  let parts = split_balanced(input, delimiter)
  case parts {
    [first, second, ..rest] ->
      Ok(#(first, string.join([second, ..rest], delimiter)))
    _ -> Error(Nil)
  }
}

fn extract_balanced(
  input: String,
  open: String,
  close: String,
) -> #(String, String) {
  let initial = ExtractState(current: [], rest: [], depth: 1, done: False)
  let state =
    input
    |> string.to_graphemes
    |> list.fold(initial, fn(state, grapheme) {
      case state.done {
        True -> ExtractState(..state, rest: [grapheme, ..state.rest])
        False -> extract_step(state, grapheme, open, close)
      }
    })

  #(
    state.current |> list.reverse |> string.join(""),
    state.rest |> list.reverse |> string.join(""),
  )
}

fn extract_step(
  state: ExtractState,
  grapheme: String,
  open: String,
  close: String,
) -> ExtractState {
  case grapheme == open {
    True ->
      ExtractState(
        ..state,
        current: [grapheme, ..state.current],
        depth: state.depth + 1,
      )
    False ->
      case grapheme == close {
        True -> {
          let depth = state.depth - 1
          case depth == 0 {
            True -> ExtractState(..state, depth: 0, done: True)
            False ->
              ExtractState(
                ..state,
                current: [grapheme, ..state.current],
                depth: depth,
              )
          }
        }
        False -> ExtractState(..state, current: [grapheme, ..state.current])
      }
  }
}

fn split_step(state: SplitState, grapheme: String, delimiter: String) {
  case
    grapheme == delimiter
    && state.angle_depth == 0
    && state.square_depth == 0
    && state.paren_depth == 0
  {
    True -> {
      let part = state.current |> list.reverse |> string.join("") |> string.trim
      SplitState(..state, current: [], parts: [part, ..state.parts])
    }
    False -> {
      let previous_grapheme = case state.current {
        [previous, ..] -> previous
        [] -> ""
      }
      let #(angle_depth, square_depth, paren_depth) =
        update_depths(
          grapheme,
          previous_grapheme,
          state.angle_depth,
          state.square_depth,
          state.paren_depth,
        )

      SplitState(
        current: [grapheme, ..state.current],
        parts: state.parts,
        angle_depth: angle_depth,
        square_depth: square_depth,
        paren_depth: paren_depth,
      )
    }
  }
}

fn finish_split(state: SplitState) -> List(String) {
  let part = state.current |> list.reverse |> string.join("") |> string.trim
  [part, ..state.parts]
  |> list.reverse
  |> list.filter(fn(part) { part != "" })
}

fn update_depths(
  grapheme: String,
  previous_grapheme: String,
  angle_depth: Int,
  square_depth: Int,
  paren_depth: Int,
) -> #(Int, Int, Int) {
  case grapheme {
    "<" -> #(angle_depth + 1, square_depth, paren_depth)
    ">" ->
      case previous_grapheme == "=" {
        True -> #(angle_depth, square_depth, paren_depth)
        False -> #(max_zero(angle_depth - 1), square_depth, paren_depth)
      }
    "[" -> #(angle_depth, square_depth + 1, paren_depth)
    "]" -> #(angle_depth, max_zero(square_depth - 1), paren_depth)
    "(" -> #(angle_depth, square_depth, paren_depth + 1)
    ")" -> #(angle_depth, square_depth, max_zero(paren_depth - 1))
    _ -> #(angle_depth, square_depth, paren_depth)
  }
}

fn strip_trailing_semicolon(input: String) -> String {
  case string.ends_with(input, ";") {
    True -> string.drop_end(input, 1) |> string.trim
    False -> input
  }
}

fn max_zero(number: Int) -> Int {
  case number < 0 {
    True -> 0
    False -> number
  }
}

fn file_error_to_string(error: simplifile.FileError) -> String {
  case error {
    simplifile.Enoent -> "file not found"
    _ -> simplifile.describe_error(error)
  }
}
