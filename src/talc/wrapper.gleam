/// Wrapper module generation for true-myth type conversions.
///
/// Generates thin JavaScript wrapper modules that convert top-level
/// Result and Option types to/from true-myth Result and Maybe types.
/// Functions without Result/Option in their signature are re-exported as-is.
import gleam/dict.{type Dict}
import gleam/int as gleam_int
import gleam/list
import gleam/option.{None, Some}
import gleam/package_interface.{
  type Function, type Module, type Type, Fn, Named, Tuple, Variable,
}
import gleam/string

/// Result of generating wrapper files for a module.
pub type WrapperResult {
  WrapperResult(
    /// Generated wrapper .mjs content
    mjs: String,
    /// Generated wrapper .d.ts content
    dts: String,
    /// Whether any functions needed wrapping (if false, module can be skipped)
    has_wrapped_functions: Bool,
  )
}

/// Generates wrapper .mjs and .d.ts files for a module.
///
/// Functions with top-level Result or Option in their return type or
/// parameters get wrapper functions that convert to/from true-myth types.
/// Other functions are re-exported directly.
pub fn generate_module_wrapper(
  module: Module,
  module_name: String,
) -> WrapperResult {
  let functions =
    dict.to_list(module.functions)
    |> list.filter(fn(pair) {
      let #(_, func) = pair
      func.implementations.uses_javascript_externals
      || !func.implementations.uses_erlang_externals
    })
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

  let analyzed =
    list.map(functions, fn(pair) {
      let #(name, func) = pair
      let needs_wrap = function_needs_wrapping(func)
      #(name, func, needs_wrap)
    })

  let has_wrapped = list.any(analyzed, fn(t) { t.2 })

  let mjs = generate_mjs(analyzed, module_name)
  let dts = generate_dts(analyzed, module_name)

  WrapperResult(mjs: mjs, dts: dts, has_wrapped_functions: has_wrapped)
}

/// Checks if a function needs wrapping (has top-level Result or Option).
fn function_needs_wrapping(func: Function) -> Bool {
  is_result_type(func.return)
  || is_option_type(func.return)
  || list.any(func.parameters, fn(p) {
    is_result_type(p.type_) || is_option_type(p.type_)
  })
}

fn is_result_type(t: Type) -> Bool {
  case t {
    Named(name: "Result", package: "", module: "gleam", ..) -> True
    _ -> False
  }
}

fn is_option_type(t: Type) -> Bool {
  case t {
    Named(name: "Option", package: "gleam_stdlib", module: "gleam/option", ..) ->
      True
    _ -> False
  }
}

// -- .mjs generation --

fn generate_mjs(
  functions: List(#(String, Function, Bool)),
  module_name: String,
) -> String {
  let wrapped = list.filter(functions, fn(t) { t.2 })

  let needs_result =
    list.any(wrapped, fn(t) {
      is_result_type({ t.1 }.return)
      || list.any({ t.1 }.parameters, fn(p) { is_result_type(p.type_) })
    })

  let needs_option =
    list.any(wrapped, fn(t) {
      is_option_type({ t.1 }.return)
      || list.any({ t.1 }.parameters, fn(p) { is_option_type(p.type_) })
    })

  let prefix = relative_prefix(module_name)
  let relative_module = prefix <> module_name <> ".mjs"

  // Build imports
  let mut_imports = []

  // Gleam runtime imports for instanceof checks
  let gleam_imports = case needs_result, needs_option {
    True, True -> ["Ok", "Error", "Some"]
    True, False -> ["Ok", "Error"]
    False, True -> ["Some"]
    False, False -> []
  }
  let mut_imports = case gleam_imports {
    [] -> mut_imports
    imports -> [
      "import { "
        <> string.join(imports, ", ")
        <> " } from \""
        <> prefix
        <> "gleam.mjs\";",
      ..mut_imports
    ]
  }

  // true-myth imports
  let tm_imports = case needs_result, needs_option {
    True, True -> [
      "import { ok, err } from \"true-myth/result\";",
      "import { just, nothing } from \"true-myth/maybe\";",
    ]
    True, False -> ["import { ok, err } from \"true-myth/result\";"]
    False, True -> ["import { just, nothing } from \"true-myth/maybe\";"]
    False, False -> []
  }
  let mut_imports = list.append(list.reverse(tm_imports), mut_imports)

  // Aliased imports for wrapped functions
  let aliased =
    list.map(wrapped, fn(t) {
      let safe_name = escape_js_reserved(t.0)
      safe_name <> " as _" <> safe_name
    })

  let mut_imports = case aliased {
    [] -> mut_imports
    imports -> [
      "import { "
        <> string.join(imports, ", ")
        <> " } from \""
        <> relative_module
        <> "\";",
      ..mut_imports
    ]
  }

  let import_block =
    list.reverse(mut_imports)
    |> string.join("\n")

  // Transparent native re-export (covers non-function exports, constants, types)
  let reexport = "\nexport * from \"" <> relative_module <> "\";\n"

  // Wrapper function bodies
  let wrapper_fns =
    list.map(wrapped, fn(t) {
      let #(name, func, _) = t
      generate_wrapper_fn_mjs(name, func)
    })
    |> string.join("\n")

  import_block <> reexport <> "\n" <> wrapper_fns
}

fn generate_wrapper_fn_mjs(name: String, func: Function) -> String {
  let safe_name = escape_js_reserved(name)
  let params =
    list.index_map(func.parameters, fn(p, i) {
      case p.label {
        Some(label) -> escape_js_reserved(label)
        None -> "p" <> gleam_int.to_string(i)
      }
    })

  let param_str = string.join(params, ", ")

  // Build argument conversion for inputs
  let converted_args =
    list.zip(params, func.parameters)
    |> list.map(fn(pair) {
      let #(param_name, p) = pair
      case is_result_type(p.type_) {
        True ->
          param_name
          <> ".isOk ? new Ok("
          <> param_name
          <> ".value) : new Error("
          <> param_name
          <> ".error)"
        False ->
          case is_option_type(p.type_) {
            True ->
              param_name
              <> ".isJust ? new Some("
              <> param_name
              <> ".value) : undefined"
            False -> param_name
          }
      }
    })

  let call = "_" <> safe_name <> "(" <> string.join(converted_args, ", ") <> ")"

  // Build return conversion
  let body = case is_result_type(func.return) {
    True ->
      "  const _r = "
      <> call
      <> ";\n  return _r instanceof Ok ? ok(_r[0]) : err(_r[0]);"
    False ->
      case is_option_type(func.return) {
        True ->
          "  const _r = "
          <> call
          <> ";\n  return _r instanceof Some ? just(_r[0]) : nothing();"
        False -> "  return " <> call <> ";"
      }
  }

  "\nexport function "
  <> safe_name
  <> "("
  <> param_str
  <> ") {\n"
  <> body
  <> "\n}\n"
}

// -- .d.ts generation --

fn generate_dts(
  functions: List(#(String, Function, Bool)),
  module_name: String,
) -> String {
  let wrapped = list.filter(functions, fn(t) { t.2 })

  let needs_result =
    list.any(wrapped, fn(t) {
      is_result_type({ t.1 }.return)
      || list.any({ t.1 }.parameters, fn(p) { is_result_type(p.type_) })
    })

  let needs_option =
    list.any(wrapped, fn(t) {
      is_option_type({ t.1 }.return)
      || list.any({ t.1 }.parameters, fn(p) { is_option_type(p.type_) })
    })

  let prefix = relative_prefix(module_name)
  let relative_module = prefix <> module_name <> ".mjs"

  // Scan wrapped functions for Gleam prelude types that need importing
  let all_wrapped_types =
    list.flat_map(wrapped, fn(t) {
      let func = t.1
      list.append(
        list.flat_map(func.parameters, fn(p) { collect_prelude_types(p.type_) }),
        collect_prelude_types(func.return),
      )
    })
    |> list.unique()
    |> list.sort(string.compare)

  // Imports
  let mut_imports = []
  let mut_imports = case all_wrapped_types {
    [] -> mut_imports
    types -> [
      "import type { "
        <> string.join(types, ", ")
        <> " } from \""
        <> prefix
        <> "gleam.d.mts\";",
      ..mut_imports
    ]
  }
  let mut_imports = case needs_result {
    True -> ["import type { Result } from \"true-myth/result\";", ..mut_imports]
    False -> mut_imports
  }
  let mut_imports = case needs_option {
    True -> ["import type { Maybe } from \"true-myth/maybe\";", ..mut_imports]
    False -> mut_imports
  }

  let import_block =
    list.reverse(mut_imports)
    |> string.join("\n")

  // Transparent native re-export
  let reexport = "\nexport * from \"" <> relative_module <> "\";\n"

  // Wrapped function declarations
  let wrapper_decls =
    list.map(wrapped, fn(t) {
      let #(name, func, _) = t
      generate_wrapper_fn_dts(name, func)
    })
    |> string.join("\n")

  let preamble = case import_block {
    "" -> ""
    block -> block <> "\n"
  }

  preamble <> reexport <> "\n" <> wrapper_decls
}

fn generate_wrapper_fn_dts(name: String, func: Function) -> String {
  let safe_name = escape_js_reserved(name)

  // Collect type variables from the function
  let vars = collect_variables(func)
  let var_map = build_variable_map(vars)

  let generics = case dict.size(var_map) {
    0 -> ""
    _ -> {
      let sorted =
        dict.to_list(var_map)
        |> list.sort(fn(a, b) { string.compare(a.1, b.1) })
        |> list.map(fn(pair) { pair.1 })
      "<" <> string.join(sorted, ", ") <> ">"
    }
  }

  let params =
    list.index_map(func.parameters, fn(p, i) {
      let param_name = case p.label {
        Some(label) -> escape_js_reserved(label)
        None -> "p" <> gleam_int.to_string(i)
      }
      param_name <> ": " <> type_to_ts(p.type_, var_map)
    })

  let return_ts = type_to_ts(func.return, var_map)

  "export declare function "
  <> safe_name
  <> generics
  <> "("
  <> string.join(params, ", ")
  <> "): "
  <> return_ts
  <> ";\n"
}

/// Maps a Gleam type to its true-myth-aware TypeScript representation.
/// Result and Option are mapped to true-myth types; everything else uses
/// basic TypeScript types.
fn type_to_ts(t: Type, vars: Dict(Int, String)) -> String {
  case t {
    Named(name: "Int", package: "", module: "gleam", ..) -> "number"
    Named(name: "Float", package: "", module: "gleam", ..) -> "number"
    Named(name: "String", package: "", module: "gleam", ..) -> "string"
    Named(name: "Bool", package: "", module: "gleam", ..) -> "boolean"
    Named(name: "Nil", package: "", module: "gleam", ..) -> "undefined"
    Named(name: "BitArray", package: "", module: "gleam", ..) -> "BitArray"
    Named(name: "UtfCodepoint", package: "", module: "gleam", ..) ->
      "UtfCodepoint"

    Named(name: "List", package: "", module: "gleam", parameters: params) ->
      case params {
        [elem] -> "List<" <> type_to_ts(elem, vars) <> ">"
        _ -> "List<unknown>"
      }

    Named(name: "Result", package: "", module: "gleam", parameters: params) ->
      case params {
        [ok_t, err_t] ->
          "Result<"
          <> type_to_ts(ok_t, vars)
          <> ", "
          <> type_to_ts(err_t, vars)
          <> ">"
        _ -> "Result<unknown, unknown>"
      }

    Named(
      name: "Option",
      package: "gleam_stdlib",
      module: "gleam/option",
      parameters: params,
    ) ->
      case params {
        [inner] -> "Maybe<" <> type_to_ts(inner, vars) <> ">"
        _ -> "Maybe<unknown>"
      }

    Variable(id: id) ->
      case dict.get(vars, id) {
        Ok(name) -> name
        Error(_) -> "unknown"
      }

    Tuple(elements: elems) -> {
      let types = list.map(elems, fn(e) { type_to_ts(e, vars) })
      "readonly [" <> string.join(types, ", ") <> "]"
    }

    Fn(parameters: params, return: ret) -> {
      let param_types =
        list.index_map(params, fn(p, i) {
          "p" <> gleam_int.to_string(i) <> ": " <> type_to_ts(p, vars)
        })
      "(" <> string.join(param_types, ", ") <> ") => " <> type_to_ts(ret, vars)
    }

    // Fallback for other named types — use the type name directly
    Named(name: n, parameters: params, ..) ->
      case params {
        [] -> n
        ps -> {
          let type_args = list.map(ps, fn(p) { type_to_ts(p, vars) })
          n <> "<" <> string.join(type_args, ", ") <> ">"
        }
      }
  }
}

/// Collects all type variable IDs from a function signature.
fn collect_variables(func: Function) -> List(Int) {
  let param_vars =
    list.flat_map(func.parameters, fn(p) { collect_type_variables(p.type_) })
  let return_vars = collect_type_variables(func.return)
  list.append(param_vars, return_vars)
  |> list.unique()
}

fn collect_type_variables(t: Type) -> List(Int) {
  case t {
    Variable(id: id) -> [id]
    Named(parameters: params, ..) ->
      list.flat_map(params, collect_type_variables)
    Tuple(elements: elems) -> list.flat_map(elems, collect_type_variables)
    Fn(parameters: params, return: ret) ->
      list.append(
        list.flat_map(params, collect_type_variables),
        collect_type_variables(ret),
      )
  }
}

/// Collects Gleam prelude type names that need importing in wrapper .d.ts.
/// These are types that map to their Gleam runtime names (not JS primitives).
fn collect_prelude_types(t: Type) -> List(String) {
  case t {
    Named(name: "List", package: "", module: "gleam", parameters: params) ->
      list.append(["List"], list.flat_map(params, collect_prelude_types))
    Named(name: "BitArray", package: "", module: "gleam", ..) -> ["BitArray"]
    Named(name: "UtfCodepoint", package: "", module: "gleam", ..) -> [
      "UtfCodepoint",
    ]
    // Primitives map to TS builtins — no import needed
    Named(name: "Int", package: "", module: "gleam", ..) -> []
    Named(name: "Float", package: "", module: "gleam", ..) -> []
    Named(name: "String", package: "", module: "gleam", ..) -> []
    Named(name: "Bool", package: "", module: "gleam", ..) -> []
    Named(name: "Nil", package: "", module: "gleam", ..) -> []
    // Result/Option handled via true-myth imports
    Named(name: "Result", package: "", module: "gleam", parameters: params) ->
      list.flat_map(params, collect_prelude_types)
    Named(
      name: "Option",
      package: "gleam_stdlib",
      module: "gleam/option",
      parameters: params,
    ) -> list.flat_map(params, collect_prelude_types)
    // Recurse into type parameters
    Named(parameters: params, ..) ->
      list.flat_map(params, collect_prelude_types)
    Tuple(elements: elems) -> list.flat_map(elems, collect_prelude_types)
    Fn(parameters: params, return: ret) ->
      list.append(
        list.flat_map(params, collect_prelude_types),
        collect_prelude_types(ret),
      )
    Variable(..) -> []
  }
}

/// Builds a mapping from variable IDs to letter names (A, B, C, ...).
fn build_variable_map(var_ids: List(Int)) -> Dict(Int, String) {
  let sorted = list.sort(var_ids, gleam_int.compare)
  list.index_map(sorted, fn(id, i) {
    let letter = case i {
      0 -> "A"
      1 -> "B"
      2 -> "C"
      3 -> "D"
      4 -> "E"
      5 -> "F"
      _ -> "T" <> gleam_int.to_string(i)
    }
    #(id, letter)
  })
  |> dict.from_list()
}

/// Escapes JavaScript reserved words by appending $.
fn escape_js_reserved(name: String) -> String {
  case name {
    "await"
    | "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "continue"
    | "debugger"
    | "default"
    | "delete"
    | "do"
    | "else"
    | "enum"
    | "export"
    | "extends"
    | "false"
    | "finally"
    | "for"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "let"
    | "new"
    | "null"
    | "return"
    | "super"
    | "switch"
    | "this"
    | "throw"
    | "true"
    | "try"
    | "typeof"
    | "undefined"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield"
    | "then" -> name <> "$"
    _ -> name
  }
}

/// Computes the relative path prefix for a wrapper module.
/// A root module like "my_lib" is wrapped at "_wrapper/my_lib.mjs" → prefix "../".
/// A nested module "my_lib/nested" is wrapped at "_wrapper/my_lib/nested.mjs" → prefix "../../".
fn relative_prefix(module_name: String) -> String {
  let depth = list.length(string.split(module_name, "/"))
  string.repeat("../", depth)
}
