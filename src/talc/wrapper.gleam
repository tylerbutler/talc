/// Wrapper module generation for true-myth type conversions.
///
/// Generates thin JavaScript wrapper modules that convert top-level
/// Result and Option types to/from true-myth Result and Maybe types.
/// Functions without Result/Option in their signature are re-exported as-is.
import gleam/dict.{type Dict}
import gleam/int as gleam_int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface.{
  type Function, type Module, type Type, Fn, Named, Tuple, Variable,
}
import gleam/string
import talc/native_types.{
  type NativeFunctionSignature, type NativeImport, type NativeModuleTypes,
}

/// Result of generating wrapper files for a module.
pub type WrapperResult {
  WrapperResult(
    /// Generated wrapper .mjs content
    mjs: String,
    /// Generated wrapper .d.ts content
    dts: String,
    /// Whether any functions needed wrapping (if false, module can be skipped)
    has_wrapped_functions: Bool,
    /// Warnings emitted while generating wrappers
    warnings: List(String),
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
  generate_module_wrapper_with_optional_native(module, module_name, None)
}

/// Generates wrapper .mjs and .d.ts files using native TypeScript declarations
/// where available.
pub fn generate_module_wrapper_with_native(
  module: Module,
  module_name: String,
  native_types: NativeModuleTypes,
) -> WrapperResult {
  generate_module_wrapper_with_optional_native(
    module,
    module_name,
    Some(native_types),
  )
}

fn generate_module_wrapper_with_optional_native(
  module: Module,
  module_name: String,
  native_types: Option(NativeModuleTypes),
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
  let #(dts, warnings) = generate_dts(analyzed, module_name, native_types)

  WrapperResult(
    mjs: mjs,
    dts: dts,
    has_wrapped_functions: has_wrapped,
    warnings: warnings,
  )
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

  let #(needs_result, needs_option) = required_conversions(wrapped)

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
  native_types: Option(NativeModuleTypes),
) -> #(String, List(String)) {
  let wrapped = list.filter(functions, fn(t) { t.2 })

  let #(needs_result, needs_option) = required_conversions(wrapped)

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
  let mut_imports =
    native_type_imports(native_types, module_name, needs_result, needs_option)
    |> list.reverse
    |> list.append(mut_imports)

  let import_block =
    list.reverse(mut_imports)
    |> string.join("\n")

  // Transparent native re-export
  let reexport = "\nexport * from \"" <> relative_module <> "\";\n"

  // Wrapped function declarations
  let generated_decls =
    list.map(wrapped, fn(t) {
      let #(name, func, _) = t
      generate_wrapper_fn_dts(name, func, native_types)
    })

  let wrapper_decls =
    generated_decls
    |> list.map(fn(result) { result.0 })
    |> string.join("\n")

  let warnings = list.flat_map(generated_decls, fn(result) { result.1 })

  let preamble = case import_block {
    "" -> ""
    block -> block <> "\n"
  }

  #(preamble <> reexport <> "\n" <> wrapper_decls, warnings)
}

fn native_type_imports(
  native_types: Option(NativeModuleTypes),
  module_name: String,
  needs_result: Bool,
  needs_option: Bool,
) -> List(String) {
  case native_types {
    None -> []
    Some(native_types) ->
      native_types.imports
      |> list.fold([], fn(imports, import_) {
        case
          rebase_native_import(import_, module_name, needs_result, needs_option)
        {
          Some(import_) -> [import_, ..imports]
          None -> imports
        }
      })
      |> list.reverse
  }
}

fn rebase_native_import(
  import_: NativeImport,
  module_name: String,
  needs_result: Bool,
  needs_option: Bool,
) -> Option(String) {
  case
    filter_conflicting_native_imports(import_.line, needs_result, needs_option)
  {
    None -> None
    Some(line) -> {
      let rebased_specifier =
        rebase_native_import_specifier(module_name, import_.specifier)
      line
      |> string.replace(
        each: "\"" <> import_.specifier <> "\"",
        with: "\"" <> rebased_specifier <> "\"",
      )
      |> Some
    }
  }
}

fn filter_conflicting_native_imports(
  line: String,
  needs_result: Bool,
  needs_option: Bool,
) -> Option(String) {
  case string.starts_with(line, "import type { ") {
    False -> Some(line)
    True -> {
      case string.split_once(line, " } from \"") {
        Error(_) -> Some(line)
        Ok(#(before_from, after_from)) -> {
          let specifiers =
            before_from
            |> string.drop_start(string.length("import type { "))
            |> native_types.split_balanced(",")
            |> list.filter(fn(specifier) {
              let local_name = native_import_local_name(specifier)
              !{
                local_name == "Result"
                && needs_result
                || local_name == "Option"
                && needs_option
              }
            })

          case specifiers {
            [] -> None
            _ ->
              Some(
                "import type { "
                <> string.join(specifiers, ", ")
                <> " } from \""
                <> after_from,
              )
          }
        }
      }
    }
  }
}

fn native_import_local_name(specifier: String) -> String {
  let specifier = string.trim(specifier)
  case string.split_once(specifier, " as ") {
    Ok(#(_imported, local)) -> string.trim(local)
    Error(_) -> specifier
  }
}

fn rebase_native_import_specifier(
  module_name: String,
  specifier: String,
) -> String {
  let target = case specifier == "./gleam.d.mts" {
    True -> "gleam.d.mts"
    False ->
      list.append(module_dir_parts(module_name), string.split(specifier, "/"))
      |> normalize_path_parts
      |> string.join("/")
  }

  relative_prefix(module_name) <> target
}

fn module_dir_parts(module_name: String) -> List(String) {
  module_name
  |> string.split("/")
  |> list_init
}

fn list_init(items: List(String)) -> List(String) {
  case items {
    [] -> []
    [_] -> []
    [first, ..rest] -> [first, ..list_init(rest)]
  }
}

fn normalize_path_parts(parts: List(String)) -> List(String) {
  parts
  |> list.fold([], fn(stack, part) {
    case part {
      "" -> stack
      "." -> stack
      ".." ->
        case stack {
          [] -> []
          [_top, ..rest] -> rest
        }
      _ -> [part, ..stack]
    }
  })
  |> list.reverse
}

fn generate_wrapper_fn_dts(
  name: String,
  func: Function,
  native_types: Option(NativeModuleTypes),
) -> #(String, List(String)) {
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

  let #(params, return_ts, warnings) = case native_types {
    None -> #(
      fallback_params(func, var_map),
      type_to_ts(func.return, var_map),
      [],
    )
    Some(native_types) -> {
      case dict.get(native_types.functions, name) {
        Ok(signature) ->
          case native_signature_to_ts(func, signature) {
            Ok(native_ts) -> #(native_ts.0, native_ts.1, [])
            Error(_) -> #(
              fallback_params(func, var_map),
              type_to_ts(func.return, var_map),
              [malformed_native_warning(name)],
            )
          }
        Error(_) -> #(
          fallback_params(func, var_map),
          type_to_ts(func.return, var_map),
          [missing_native_warning(name)],
        )
      }
    }
  }

  #(
    "export declare function "
      <> safe_name
      <> generics
      <> "("
      <> string.join(params, ", ")
      <> "): "
      <> return_ts
      <> ";\n",
    warnings,
  )
}

fn required_conversions(
  functions: List(#(String, Function, Bool)),
) -> #(Bool, Bool) {
  #(
    list.any(functions, fn(t) {
      is_result_type({ t.1 }.return)
      || list.any({ t.1 }.parameters, fn(p) { is_result_type(p.type_) })
    }),
    list.any(functions, fn(t) {
      is_option_type({ t.1 }.return)
      || list.any({ t.1 }.parameters, fn(p) { is_option_type(p.type_) })
    }),
  )
}

fn fallback_params(func: Function, var_map: Dict(Int, String)) -> List(String) {
  list.index_map(func.parameters, fn(p, i) {
    let param_name = case p.label {
      Some(label) -> escape_js_reserved(label)
      None -> "p" <> gleam_int.to_string(i)
    }
    param_name <> ": " <> type_to_ts(p.type_, var_map)
  })
}

fn native_signature_to_ts(
  func: Function,
  signature: NativeFunctionSignature,
) -> Result(#(List(String), String), Nil) {
  case list.length(func.parameters) == list.length(signature.parameters) {
    False -> Error(Nil)
    True -> {
      let indexed_params =
        list.zip(func.parameters, signature.parameters)
        |> list.index_map(fn(pair, i) { #(i, pair) })

      case
        list.try_fold(indexed_params, [], fn(params, indexed_pair) {
          let #(i, pair) = indexed_pair
          let #(param, native_param) = pair
          let #(_, native_type) = native_param
          let param_name = case param.label {
            Some(label) -> escape_js_reserved(label)
            None -> "p" <> gleam_int.to_string(i)
          }
          case rewrite_native_type_result(param.type_, native_type) {
            Ok(param_type) -> Ok([param_name <> ": " <> param_type, ..params])
            Error(_) -> Error(Nil)
          }
        })
      {
        Ok(params) ->
          case rewrite_native_type_result(func.return, signature.return_type) {
            Ok(return_ts) -> Ok(#(list.reverse(params), return_ts))
            Error(_) -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn rewrite_native_type_result(gleam_type: Type, native_type: String) {
  case is_result_type(gleam_type) {
    True -> rewrite_top_level_result(native_type)
    False ->
      case is_option_type(gleam_type) {
        True -> rewrite_top_level_option(native_type)
        False -> Ok(native_type)
      }
  }
}

fn rewrite_top_level_result(native_type: String) -> Result(String, Nil) {
  case top_level_type_arguments(native_type, "_.Result<", "Result<") {
    Ok([ok_type, error_type]) ->
      Ok("Result<" <> ok_type <> ", " <> error_type <> ">")
    _ -> Error(Nil)
  }
}

fn rewrite_top_level_option(native_type: String) -> Result(String, Nil) {
  case top_level_type_arguments(native_type, "_.Option<", "Option<") {
    Ok([inner_type]) -> Ok("Maybe<" <> inner_type <> ">")
    _ -> Error(Nil)
  }
}

fn top_level_type_arguments(
  native_type: String,
  namespaced_prefix: String,
  bare_prefix: String,
) -> Result(List(String), Nil) {
  let native_type = string.trim(native_type)
  case string.ends_with(native_type, ">") {
    False -> Error(Nil)
    True -> {
      case string.starts_with(native_type, namespaced_prefix) {
        True ->
          native_type
          |> string.drop_start(string.length(namespaced_prefix))
          |> string.drop_end(1)
          |> native_types.split_balanced(",")
          |> Ok
        False ->
          case string.starts_with(native_type, bare_prefix) {
            True ->
              native_type
              |> string.drop_start(string.length(bare_prefix))
              |> string.drop_end(1)
              |> native_types.split_balanced(",")
              |> Ok
            False -> Error(Nil)
          }
      }
    }
  }
}

fn missing_native_warning(name: String) -> String {
  "Missing native TypeScript signature for wrapped function "
  <> name
  <> "; falling back to generated types"
}

fn malformed_native_warning(name: String) -> String {
  "Malformed native TypeScript signature for wrapped function "
  <> name
  <> "; falling back to generated types"
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
