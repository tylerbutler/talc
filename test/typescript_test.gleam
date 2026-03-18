import gleam/list
import gleam/package_interface.{Fn, Named, Tuple, Variable}
import startest/expect
import talc/typescript

pub fn int_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Int", "", "gleam", []))
  ts |> expect.to_equal("number")
}

pub fn float_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Float", "", "gleam", []))
  ts |> expect.to_equal("number")
}

pub fn string_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("String", "", "gleam", []))
  ts |> expect.to_equal("string")
}

pub fn bool_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Bool", "", "gleam", []))
  ts |> expect.to_equal("boolean")
}

pub fn nil_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Nil", "", "gleam", []))
  ts |> expect.to_equal("undefined")
}

pub fn bit_array_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("BitArray", "", "gleam", []))
  ts |> expect.to_equal("Uint8Array")
}

pub fn list_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("List", "", "gleam", [Named("String", "", "gleam", [])]),
    )
  ts |> expect.to_equal("Array<string>")
}

pub fn list_generic_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(ctx, Named("List", "", "gleam", [Variable(1)]))
  ts |> expect.to_equal("Array<A>")
}

pub fn result_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Result", "", "gleam", [
        Named("String", "", "gleam", []),
        Named("Nil", "", "gleam", []),
      ]),
    )
  ts
  |> expect.to_equal(
    "{ readonly ok: true; readonly value: string } | { readonly ok: false; readonly error: undefined }",
  )
}

pub fn option_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Option", "gleam_stdlib", "gleam/option", [
        Named("Int", "", "gleam", []),
      ]),
    )
  ts |> expect.to_equal("number | undefined")
}

pub fn dict_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Dict", "gleam_stdlib", "gleam/dict", [
        Named("String", "", "gleam", []),
        Named("Int", "", "gleam", []),
      ]),
    )
  ts |> expect.to_equal("Map<string, number>")
}

pub fn set_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Set", "gleam_stdlib", "gleam/set", [
        Named("String", "", "gleam", []),
      ]),
    )
  ts |> expect.to_equal("Set<string>")
}

pub fn dynamic_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Dynamic", "gleam_stdlib", "gleam/dynamic", []),
    )
  ts |> expect.to_equal("unknown /* gleam.Dynamic */")
}

pub fn variable_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts1, ctx) = typescript.type_to_ts(ctx, Variable(1))
  let #(ts2, ctx) = typescript.type_to_ts(ctx, Variable(2))
  let #(ts3, _) = typescript.type_to_ts(ctx, Variable(1))
  ts1 |> expect.to_equal("A")
  ts2 |> expect.to_equal("B")
  ts3 |> expect.to_equal("A")
}

pub fn tuple_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Tuple([Named("String", "", "gleam", []), Named("Int", "", "gleam", [])]),
    )
  ts |> expect.to_equal("readonly [string, number]")
}

pub fn fn_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Fn([Named("String", "", "gleam", [])], Named("Bool", "", "gleam", [])),
    )
  ts |> expect.to_equal("(p0: string) => boolean")
}

pub fn fn_generic_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Fn([Variable(1)], Variable(2)))
  ts |> expect.to_equal("(p0: A) => B")
}

pub fn external_package_type_warning_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) =
    typescript.type_to_ts(
      ctx,
      Named("DateTime", "some_package", "some/module", []),
    )
  ts |> expect.to_equal("unknown")
  list.length(ctx.warnings) |> expect.to_equal(1)
}

pub fn external_json_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) =
    typescript.type_to_ts(ctx, Named("Json", "gleam_json", "gleam/json", []))
  ts |> expect.to_equal("string")
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn external_http_method_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) =
    typescript.type_to_ts(ctx, Named("Method", "gleam_http", "gleam/http", []))
  ts
  |> expect.to_equal(
    "\"GET\" | \"POST\" | \"PUT\" | \"DELETE\" | \"PATCH\" | \"HEAD\" | \"OPTIONS\"",
  )
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn external_http_scheme_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) =
    typescript.type_to_ts(ctx, Named("Scheme", "gleam_http", "gleam/http", []))
  ts |> expect.to_equal("\"http\" | \"https\"")
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn external_birl_time_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) = typescript.type_to_ts(ctx, Named("Time", "birl", "birl", []))
  ts |> expect.to_equal("Date")
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn external_subject_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) =
    typescript.type_to_ts(
      ctx,
      Named("Subject", "gleam_erlang", "gleam/erlang/process", [
        Named("String", "", "gleam", []),
      ]),
    )
  ts |> expect.to_equal("{ readonly phantom: string }")
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn custom_external_type_mapping_test() {
  let ctx = typescript.new_context("test", "test_module")
  let ctx =
    typescript.add_external_type(
      ctx,
      #("my_pkg", "my_pkg/types", "MyWidget"),
      typescript.TypeMapping(arity: 0, template: fn(_) { "HTMLElement" }),
    )
  let #(ts, ctx) =
    typescript.type_to_ts(ctx, Named("MyWidget", "my_pkg", "my_pkg/types", []))
  ts |> expect.to_equal("HTMLElement")
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn external_mapping_with_params_test() {
  let ctx = typescript.new_context("test", "test_module")
  let ctx =
    typescript.add_external_type(
      ctx,
      #("my_pkg", "my_pkg/types", "Container"),
      typescript.TypeMapping(arity: 1, template: fn(params) {
        case params {
          [t] -> "Container<" <> t <> ">"
          _ -> "unknown"
        }
      }),
    )
  let #(ts, ctx) =
    typescript.type_to_ts(
      ctx,
      Named("Container", "my_pkg", "my_pkg/types", [
        Named("Int", "", "gleam", []),
      ]),
    )
  ts |> expect.to_equal("Container<number>")
  list.length(ctx.warnings) |> expect.to_equal(0)
}

pub fn same_package_type_test() {
  let ctx = typescript.new_context("mylib", "mylib_module")
  let #(ts, _) =
    typescript.type_to_ts(ctx, Named("MyType", "mylib", "mylib/types", []))
  ts |> expect.to_equal("MyType")
}

pub fn same_package_generic_type_test() {
  let ctx = typescript.new_context("mylib", "mylib_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Box", "mylib", "mylib/types", [Variable(1)]),
    )
  ts |> expect.to_equal("Box<A>")
}

pub fn generics_string_empty_test() {
  let ctx = typescript.new_context("test", "test_module")
  typescript.generics_string(ctx) |> expect.to_equal("")
}

pub fn generics_string_with_vars_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(_, ctx) = typescript.type_to_ts(ctx, Variable(1))
  let #(_, ctx) = typescript.type_to_ts(ctx, Variable(2))
  typescript.generics_string(ctx) |> expect.to_equal("<A, B>")
}

pub fn relative_import_path_sibling_test() {
  // birch/handler → birch/level (same parent dir)
  typescript.relative_import_path("birch/handler", "birch/level")
  |> expect.to_equal("./level.js")
}

pub fn relative_import_path_parent_to_child_test() {
  // birch → birch/level (root to subdir)
  typescript.relative_import_path("birch", "birch/level")
  |> expect.to_equal("./birch/level.js")
}

pub fn relative_import_path_child_to_uncle_test() {
  // birch/handler/console → birch/level (up two, down one)
  typescript.relative_import_path("birch/handler/console", "birch/level")
  |> expect.to_equal("../level.js")
}

pub fn relative_import_path_deep_to_root_test() {
  // birch/handler → _gleam (up one level)
  typescript.relative_import_path("birch/handler", "_gleam")
  |> expect.to_equal("../_gleam.js")
}
