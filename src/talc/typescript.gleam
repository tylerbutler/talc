/// Mapping Gleam types to TypeScript type representations.
///
/// This module converts `gleam/package_interface.Type` values into
/// TypeScript type strings, handling all primitive types, standard
/// library types, generics, function types, and tuples.
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/package_interface.{
  type Parameter, type Type, type TypeDefinition, Fn, Named, Tuple, Variable,
}
import gleam/string

/// Context for tracking type variable → generic letter mappings.
pub type TypeContext {
  TypeContext(
    /// Maps Variable IDs to generic parameter names (A, B, C, ...)
    variables: Dict(Int, String),
    /// Next letter index to assign
    next_var: Int,
    /// Warnings accumulated during type mapping
    warnings: List(String),
    /// The package name (for resolving same-package types)
    package_name: String,
    /// The current module being emitted (for tracking cross-module imports)
    current_module: String,
    /// Maps module paths to lists of type names that need importing
    imports: Dict(String, List(String)),
  )
}

/// Creates a new TypeContext for a given package and module.
pub fn new_context(
  package_name: String,
  current_module: String,
) -> TypeContext {
  TypeContext(
    variables: dict.new(),
    next_var: 0,
    warnings: [],
    package_name: package_name,
    current_module: current_module,
    imports: dict.new(),
  )
}

/// Pre-scans a function signature to discover all type variables
/// and assign them consistent generic letters.
pub fn scan_function(
  ctx: TypeContext,
  params: List(Parameter),
  return: Type,
) -> TypeContext {
  let ctx = list.fold(params, ctx, fn(c, p) { scan_type(c, p.type_) })
  scan_type(ctx, return)
}

/// Pre-scans a type definition to discover all type variables.
pub fn scan_type_definition(
  ctx: TypeContext,
  type_def: TypeDefinition,
) -> TypeContext {
  list.fold(type_def.constructors, ctx, fn(c, constructor) {
    list.fold(constructor.parameters, c, fn(c2, p) { scan_type(c2, p.type_) })
  })
}

/// Recursively scans a type to discover variables.
fn scan_type(ctx: TypeContext, type_: Type) -> TypeContext {
  case type_ {
    Variable(id) -> register_variable(ctx, id)
    Named(_, _, _, parameters) ->
      list.fold(parameters, ctx, fn(c, p) { scan_type(c, p) })
    Tuple(elements) -> list.fold(elements, ctx, fn(c, e) { scan_type(c, e) })
    Fn(parameters, return) -> {
      let ctx = list.fold(parameters, ctx, fn(c, p) { scan_type(c, p) })
      scan_type(ctx, return)
    }
  }
}

/// Registers a variable ID and assigns it a generic letter if not already known.
fn register_variable(ctx: TypeContext, id: Int) -> TypeContext {
  case dict.get(ctx.variables, id) {
    Ok(_) -> ctx
    Error(_) -> {
      let letter = var_letter(ctx.next_var)
      TypeContext(
        ..ctx,
        variables: dict.insert(ctx.variables, id, letter),
        next_var: ctx.next_var + 1,
      )
    }
  }
}

/// Converts an index to a generic letter: 0→A, 1→B, ..., 25→Z, 26→A1, etc.
fn var_letter(index: Int) -> String {
  let base = index % 26
  let suffix = index / 26
  let letter = case base {
    0 -> "A"
    1 -> "B"
    2 -> "C"
    3 -> "D"
    4 -> "E"
    5 -> "F"
    6 -> "G"
    7 -> "H"
    8 -> "I"
    9 -> "J"
    10 -> "K"
    11 -> "L"
    12 -> "M"
    13 -> "N"
    14 -> "O"
    15 -> "P"
    16 -> "Q"
    17 -> "R"
    18 -> "S"
    19 -> "T"
    20 -> "U"
    21 -> "V"
    22 -> "W"
    23 -> "X"
    24 -> "Y"
    25 -> "Z"
    _ -> "T"
  }
  case suffix {
    0 -> letter
    n -> letter <> int.to_string(n)
  }
}

/// Maps a Gleam Type to a TypeScript type string.
pub fn type_to_ts(ctx: TypeContext, type_: Type) -> #(String, TypeContext) {
  case type_ {
    // Type variables → generic parameter letters
    Variable(id) -> {
      case dict.get(ctx.variables, id) {
        Ok(letter) -> #(letter, ctx)
        Error(_) -> {
          // Variable not pre-scanned; register it now
          let ctx = register_variable(ctx, id)
          let assert Ok(letter) = dict.get(ctx.variables, id)
          #(letter, ctx)
        }
      }
    }

    // Tuple types → readonly tuple
    Tuple(elements) -> {
      let #(element_types, ctx) = map_types(ctx, elements)
      #("readonly [" <> string.join(element_types, ", ") <> "]", ctx)
    }

    // Function types → arrow function
    Fn(parameters, return) -> {
      let #(param_types, ctx) = map_types(ctx, parameters)
      let param_strs =
        list.index_map(param_types, fn(t, i) {
          "p" <> int.to_string(i) <> ": " <> t
        })
      let #(ret_type, ctx) = type_to_ts(ctx, return)
      #("(" <> string.join(param_strs, ", ") <> ") => " <> ret_type, ctx)
    }

    // Named types — match on package/module/name
    Named(name, package, module, parameters) ->
      named_type_to_ts(ctx, name, package, module, parameters)
  }
}

/// Maps a named type to TypeScript.
fn named_type_to_ts(
  ctx: TypeContext,
  name: String,
  package: String,
  module: String,
  parameters: List(Type),
) -> #(String, TypeContext) {
  case package, module, name {
    // Gleam prelude types (package="" module="gleam")
    "", "gleam", "Int" -> #("number", ctx)
    "", "gleam", "Float" -> #("number", ctx)
    "", "gleam", "String" -> #("string", ctx)
    "", "gleam", "Bool" -> #("boolean", ctx)
    "", "gleam", "Nil" -> #("undefined", ctx)
    "", "gleam", "BitArray" -> #("Uint8Array", ctx)
    "", "gleam", "UtfCodepoint" -> #("number", ctx)

    // List
    "", "gleam", "List" -> {
      case parameters {
        [elem] -> {
          let #(elem_ts, ctx) = type_to_ts(ctx, elem)
          #("Array<" <> elem_ts <> ">", ctx)
        }
        _ -> #("Array<unknown>", ctx)
      }
    }

    // Result
    "", "gleam", "Result" -> {
      case parameters {
        [ok_type, err_type] -> {
          let #(ok_ts, ctx) = type_to_ts(ctx, ok_type)
          let #(err_ts, ctx) = type_to_ts(ctx, err_type)
          #(
            "{ readonly ok: true; readonly value: "
              <> ok_ts
              <> " } | { readonly ok: false; readonly error: "
              <> err_ts
              <> " }",
            ctx,
          )
        }
        _ -> #("unknown", ctx)
      }
    }

    // Option (gleam_stdlib)
    "gleam_stdlib", "gleam/option", "Option" -> {
      case parameters {
        [inner] -> {
          let #(inner_ts, ctx) = type_to_ts(ctx, inner)
          #(inner_ts <> " | undefined", ctx)
        }
        _ -> #("unknown", ctx)
      }
    }

    // Dict
    "gleam_stdlib", "gleam/dict", "Dict" -> {
      case parameters {
        [key, value] -> {
          let #(key_ts, ctx) = type_to_ts(ctx, key)
          let #(val_ts, ctx) = type_to_ts(ctx, value)
          #("Map<" <> key_ts <> ", " <> val_ts <> ">", ctx)
        }
        _ -> #("Map<unknown, unknown>", ctx)
      }
    }

    // Set
    "gleam_stdlib", "gleam/set", "Set" -> {
      case parameters {
        [elem] -> {
          let #(elem_ts, ctx) = type_to_ts(ctx, elem)
          #("Set<" <> elem_ts <> ">", ctx)
        }
        _ -> #("Set<unknown>", ctx)
      }
    }

    // Dynamic
    "gleam_stdlib", "gleam/dynamic", "Dynamic" -> #("unknown", ctx)

    // Order (from gleam_stdlib)
    "gleam_stdlib", "gleam/order", "Order" -> #("\"Lt\" | \"Eq\" | \"Gt\"", ctx)

    // Same-package types → reference by name with generics
    pkg, module, n if pkg == ctx.package_name || pkg == "" -> {
      // Track import if from a different module within same package
      let ctx = case
        pkg == ctx.package_name && module != ctx.current_module
      {
        True -> add_import(ctx, module, n)
        False -> ctx
      }
      case parameters {
        [] -> #(n, ctx)
        params -> {
          let #(param_types, ctx) = map_types(ctx, params)
          #(n <> "<" <> string.join(param_types, ", ") <> ">", ctx)
        }
      }
    }

    // External package types → unknown with warning
    _, _, _ -> {
      let warning =
        "Cannot map type "
        <> module
        <> "."
        <> name
        <> " from package "
        <> package
        <> " — emitting as unknown"
      #("unknown", add_warning(ctx, warning))
    }
  }
}

/// Returns the generic parameters string (e.g. "<A, B>") for a context,
/// or empty string if no generics.
pub fn generics_string(ctx: TypeContext) -> String {
  case dict.size(ctx.variables) {
    0 -> ""
    _ -> {
      let letters =
        dict.to_list(ctx.variables)
        |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
        |> list.map(fn(pair) { pair.1 })
      "<" <> string.join(letters, ", ") <> ">"
    }
  }
}

/// Maps a list of types, threading the context through.
fn map_types(
  ctx: TypeContext,
  types: List(Type),
) -> #(List(String), TypeContext) {
  list.fold(types, #([], ctx), fn(acc, t) {
    let #(results, ctx) = acc
    let #(ts, ctx) = type_to_ts(ctx, t)
    #(list.append(results, [ts]), ctx)
  })
}

fn add_warning(ctx: TypeContext, warning: String) -> TypeContext {
  TypeContext(..ctx, warnings: list.append(ctx.warnings, [warning]))
}

/// Records a type name as needing to be imported from the given module.
fn add_import(
  ctx: TypeContext,
  module: String,
  type_name: String,
) -> TypeContext {
  let current_imports = case dict.get(ctx.imports, module) {
    Ok(names) -> names
    Error(_) -> []
  }
  let updated = case list.contains(current_imports, type_name) {
    True -> current_imports
    False -> list.append(current_imports, [type_name])
  }
  TypeContext(..ctx, imports: dict.insert(ctx.imports, module, updated))
}

/// Generates import statements for all tracked cross-module type references.
pub fn imports_string(ctx: TypeContext) -> String {
  case dict.size(ctx.imports) {
    0 -> ""
    _ -> {
      let import_lines =
        dict.to_list(ctx.imports)
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> list.map(fn(pair) {
          let #(module, names) = pair
          let sorted_names = list.sort(names, string.compare)
          let path = relative_import_path(ctx.current_module, module)
          "import type { "
          <> string.join(sorted_names, ", ")
          <> " } from \""
          <> path
          <> "\";"
        })
      string.join(import_lines, "\n") <> "\n\n"
    }
  }
}

/// Computes a relative import path from one module to another.
/// e.g. from "birch/handler" to "birch/level" → "./level.mjs"
/// e.g. from "birch" to "birch/handler" → "./birch/handler.mjs"
fn relative_import_path(from_module: String, to_module: String) -> String {
  let from_parts = string.split(from_module, "/")
  let to_parts = string.split(to_module, "/")

  // Directory parts = all parts except the last (filename)
  let from_dir = list.take(from_parts, list.length(from_parts) - 1)
  let to_dir = list.take(to_parts, list.length(to_parts) - 1)

  let common_len = common_prefix_length(from_dir, to_dir)
  let ups = list.length(from_dir) - common_len
  let down_parts = list.drop(to_parts, common_len)

  let up_str = string.repeat("../", ups)
  let down_str = string.join(down_parts, "/")

  case ups {
    0 -> "./" <> down_str <> ".js"
    _ -> up_str <> down_str <> ".js"
  }
}

/// Counts the length of the common prefix between two lists of strings.
fn common_prefix_length(a: List(String), b: List(String)) -> Int {
  case a, b {
    [ha, ..ta], [hb, ..tb] if ha == hb -> 1 + common_prefix_length(ta, tb)
    _, _ -> 0
  }
}
