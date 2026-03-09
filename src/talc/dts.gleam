/// TypeScript declaration file (.d.ts) generation.
///
/// This module takes a parsed Gleam module from the package interface
/// and emits TypeScript declaration strings suitable for writing to
/// `.d.ts` files.
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/package_interface.{type Function, type Module, type TypeDefinition}
import gleam/string
import talc/typescript.{type TypeContext}

/// Result of emitting a .d.ts file for a module.
pub type EmitResult {
  EmitResult(
    /// The generated .d.ts content
    content: String,
    /// Warnings encountered during emission
    warnings: List(String),
  )
}

/// Emits a .d.ts file for a single Gleam module.
pub fn emit_module(
  module: Module,
  package_name: String,
  module_name: String,
) -> EmitResult {
  let ctx = typescript.new_context(package_name, module_name)

  // Emit type definitions (records, ADTs, opaque)
  let #(type_decls, ctx) =
    dict.to_list(module.types)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.fold(#([], ctx), fn(acc, pair) {
      let #(decls, ctx) = acc
      let #(name, type_def) = pair
      let #(decl, ctx) = emit_type_definition(ctx, name, type_def)
      #(list.append(decls, [decl]), ctx)
    })

  // Emit function declarations
  let #(func_decls, ctx) =
    dict.to_list(module.functions)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.fold(#([], ctx), fn(acc, pair) {
      let #(decls, ctx) = acc
      let #(name, func) = pair
      // Only emit functions that can run on JavaScript
      case func.implementations.can_run_on_javascript {
        True -> {
          let #(decl, ctx) = emit_function(ctx, name, func)
          #(list.append(decls, [decl]), ctx)
        }
        False -> #(decls, ctx)
      }
    })

  let all_decls = list.append(type_decls, func_decls)
  let imports = typescript.imports_string(ctx)

  let content =
    imports <> string.join(all_decls, "\n\n") <> "\n"

  EmitResult(content: content, warnings: ctx.warnings)
}

/// Emits a type definition as TypeScript.
fn emit_type_definition(
  ctx: TypeContext,
  name: String,
  type_def: TypeDefinition,
) -> #(String, TypeContext) {
  case type_def.constructors {
    // Opaque type — no constructors exposed
    [] -> {
      let warning = "Opaque type " <> name <> " — emitting as branded type"
      let ctx = add_warning(ctx, warning)
      let decl =
        doc_comment(type_def.documentation)
        <> "declare const "
        <> name
        <> ": unique symbol;\n"
        <> "export type "
        <> name
        <> " = { readonly __opaque: typeof "
        <> name
        <> " };"
      #(decl, ctx)
    }

    // Single constructor — emit as interface (record type)
    [constructor] -> {
      let ctx = typescript.scan_type_definition(ctx, type_def)
      let generics = type_params_string(type_def.parameters, ctx)

      let #(fields, ctx) =
        list.fold(constructor.parameters, #([], ctx), fn(acc, param) {
          let #(fields, ctx) = acc
          let field_name = case param.label {
            Some(label) -> label
            None -> "field_" <> int.to_string(list.length(fields))
          }
          let #(ts_type, ctx) = typescript.type_to_ts(ctx, param.type_)
          let field = "  readonly " <> field_name <> ": " <> ts_type <> ";"
          #(list.append(fields, [field]), ctx)
        })

      let decl =
        doc_comment(type_def.documentation)
        <> "export interface "
        <> name
        <> generics
        <> " {\n"
        <> string.join(fields, "\n")
        <> case fields {
          [] -> ""
          _ -> "\n"
        }
        <> "}"

      #(decl, ctx)
    }

    // Multiple constructors — emit as class-based union (ADT)
    // Uses `declare class` to match Gleam's JS runtime representation,
    // enabling `instanceof` narrowing.
    constructors -> {
      let ctx = typescript.scan_type_definition(ctx, type_def)
      let generics = type_params_string(type_def.parameters, ctx)

      let #(classes, ctx) =
        list.fold(constructors, #([], ctx), fn(acc, constructor) {
          let #(cls_list, ctx) = acc

          let #(fields, ctx) =
            list.index_fold(
              constructor.parameters,
              #([], ctx),
              fn(facc, param, index) {
                let #(flds, ctx) = facc
                let field_name = case param.label {
                  Some(label) -> label
                  None -> int.to_string(index)
                }
                let #(ts_type, ctx) = typescript.type_to_ts(ctx, param.type_)
                let field =
                  "  readonly " <> field_name <> ": " <> ts_type <> ";"
                #(list.append(flds, [field]), ctx)
              },
            )

          let cls =
            "export declare class "
            <> constructor.name
            <> generics
            <> " {\n"
            <> string.join(fields, "\n")
            <> case fields {
              [] -> ""
              _ -> "\n"
            }
            <> "}"

          #(list.append(cls_list, [cls]), ctx)
        })

      let constructor_names =
        list.map(constructors, fn(c) { c.name <> generics })
      let union_decl =
        doc_comment(type_def.documentation)
        <> string.join(classes, "\n\n")
        <> "\n\nexport type "
        <> name
        <> generics
        <> " = "
        <> string.join(constructor_names, " | ")
        <> ";"

      #(union_decl, ctx)
    }
  }
}

/// Emits a function declaration.
fn emit_function(
  ctx: TypeContext,
  name: String,
  func: Function,
) -> #(String, TypeContext) {
  // Create a fresh context for this function's generics
  let fn_ctx = typescript.new_context(ctx.package_name, ctx.current_module)
  let fn_ctx =
    typescript.TypeContext(
      ..fn_ctx,
      warnings: ctx.warnings,
      imports: ctx.imports,
    )
  let fn_ctx = typescript.scan_function(fn_ctx, func.parameters, func.return)

  let #(param_strs, fn_ctx) =
    list.index_fold(func.parameters, #([], fn_ctx), fn(acc, param, index) {
      let #(params, ctx) = acc
      let param_name = case param.label {
        Some(label) -> label
        None -> "p" <> int.to_string(index)
      }
      let #(ts_type, ctx) = typescript.type_to_ts(ctx, param.type_)
      let param_str = param_name <> ": " <> ts_type
      #(list.append(params, [param_str]), ctx)
    })

  let #(return_ts, fn_ctx) = typescript.type_to_ts(fn_ctx, func.return)
  let generics = typescript.generics_string(fn_ctx)

  let js_name = escape_js_reserved(name)

  let decl =
    doc_comment(func.documentation)
    <> "export declare function "
    <> js_name
    <> generics
    <> "("
    <> string.join(param_strs, ", ")
    <> "): "
    <> return_ts
    <> ";"

  // Carry warnings and imports back to the main context
  let ctx =
    typescript.TypeContext(
      ..ctx,
      warnings: fn_ctx.warnings,
      imports: fn_ctx.imports,
    )
  #(decl, ctx)
}

/// Generates generic type parameters string from parameter count.
/// Uses the context's variable mappings to get consistent letters.
fn type_params_string(count: Int, ctx: TypeContext) -> String {
  case count {
    0 -> ""
    _ -> {
      let sorted_vars =
        dict.to_list(ctx.variables)
        |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
        |> list.map(fn(pair: #(Int, String)) { pair.1 })
        |> list.take(count)
      case sorted_vars {
        [] -> ""
        l -> "<" <> string.join(l, ", ") <> ">"
      }
    }
  }
}

/// Formats an optional documentation string as a JSDoc comment.
fn doc_comment(doc: option.Option(String)) -> String {
  case doc {
    None -> ""
    Some(text) -> {
      let lines = string.split(text, "\n")
      case lines {
        [] -> ""
        _ ->
          "/**\n"
          <> string.join(list.map(lines, fn(line) { " *" <> line }), "\n")
          <> "\n */\n"
      }
    }
  }
}

fn add_warning(ctx: TypeContext, warning: String) -> TypeContext {
  typescript.TypeContext(..ctx, warnings: list.append(ctx.warnings, [warning]))
}

/// Appends `$` to JavaScript/TypeScript reserved words to match Gleam's
/// JS code generation. Without this, the .d.ts declarations would use
/// names like `new` or `null` which are not valid identifiers.
fn escape_js_reserved(name: String) -> String {
  case name {
    "await" | "arguments" | "break" | "case" | "catch" | "class" | "const"
    | "continue" | "debugger" | "default" | "delete" | "do" | "else" | "enum"
    | "eval" | "export" | "extends" | "false" | "finally" | "for"
    | "function" | "if" | "implements" | "import" | "in" | "instanceof"
    | "interface" | "let" | "new" | "null" | "package" | "private"
    | "protected" | "public" | "return" | "static" | "super" | "switch"
    | "this" | "throw" | "true" | "try" | "typeof" | "undefined" | "var"
    | "void" | "while" | "with" | "yield"
    -> name <> "$"
    _ -> name
  }
}
