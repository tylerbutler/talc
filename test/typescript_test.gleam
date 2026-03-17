import gleam/list
import gleam/package_interface.{Fn, Named, Tuple, Variable}
import gleeunit/should
import talc/typescript

pub fn int_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Int", "", "gleam", []))
  ts |> should.equal("number")
}

pub fn float_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Float", "", "gleam", []))
  ts |> should.equal("number")
}

pub fn string_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("String", "", "gleam", []))
  ts |> should.equal("string")
}

pub fn bool_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Bool", "", "gleam", []))
  ts |> should.equal("boolean")
}

pub fn nil_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("Nil", "", "gleam", []))
  ts |> should.equal("undefined")
}

pub fn bit_array_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Named("BitArray", "", "gleam", []))
  ts |> should.equal("Uint8Array")
}

pub fn list_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("List", "", "gleam", [Named("String", "", "gleam", [])]),
    )
  ts |> should.equal("Array<string>")
}

pub fn list_generic_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(ctx, Named("List", "", "gleam", [Variable(1)]))
  ts |> should.equal("Array<A>")
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
  |> should.equal(
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
  ts |> should.equal("number | undefined")
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
  ts |> should.equal("Map<string, number>")
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
  ts |> should.equal("Set<string>")
}

pub fn dynamic_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Dynamic", "gleam_stdlib", "gleam/dynamic", []),
    )
  ts |> should.equal("unknown")
}

pub fn variable_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts1, ctx) = typescript.type_to_ts(ctx, Variable(1))
  let #(ts2, ctx) = typescript.type_to_ts(ctx, Variable(2))
  let #(ts3, _) = typescript.type_to_ts(ctx, Variable(1))
  ts1 |> should.equal("A")
  ts2 |> should.equal("B")
  ts3 |> should.equal("A")
}

pub fn tuple_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Tuple([Named("String", "", "gleam", []), Named("Int", "", "gleam", [])]),
    )
  ts |> should.equal("readonly [string, number]")
}

pub fn fn_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Fn([Named("String", "", "gleam", [])], Named("Bool", "", "gleam", [])),
    )
  ts |> should.equal("(p0: string) => boolean")
}

pub fn fn_generic_type_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, _) = typescript.type_to_ts(ctx, Fn([Variable(1)], Variable(2)))
  ts |> should.equal("(p0: A) => B")
}

pub fn external_package_type_warning_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(ts, ctx) =
    typescript.type_to_ts(
      ctx,
      Named("DateTime", "some_package", "some/module", []),
    )
  ts |> should.equal("unknown")
  list.length(ctx.warnings) |> should.equal(1)
}

pub fn same_package_type_test() {
  let ctx = typescript.new_context("mylib", "mylib_module")
  let #(ts, _) =
    typescript.type_to_ts(ctx, Named("MyType", "mylib", "mylib/types", []))
  ts |> should.equal("MyType")
}

pub fn same_package_generic_type_test() {
  let ctx = typescript.new_context("mylib", "mylib_module")
  let #(ts, _) =
    typescript.type_to_ts(
      ctx,
      Named("Box", "mylib", "mylib/types", [Variable(1)]),
    )
  ts |> should.equal("Box<A>")
}

pub fn generics_string_empty_test() {
  let ctx = typescript.new_context("test", "test_module")
  typescript.generics_string(ctx) |> should.equal("")
}

pub fn generics_string_with_vars_test() {
  let ctx = typescript.new_context("test", "test_module")
  let #(_, ctx) = typescript.type_to_ts(ctx, Variable(1))
  let #(_, ctx) = typescript.type_to_ts(ctx, Variable(2))
  typescript.generics_string(ctx) |> should.equal("<A, B>")
}

pub fn relative_import_path_sibling_test() {
  // birch/handler → birch/level (same parent dir)
  typescript.relative_import_path("birch/handler", "birch/level")
  |> should.equal("./level.js")
}

pub fn relative_import_path_parent_to_child_test() {
  // birch → birch/level (root to subdir)
  typescript.relative_import_path("birch", "birch/level")
  |> should.equal("./birch/level.js")
}

pub fn relative_import_path_child_to_uncle_test() {
  // birch/handler/console → birch/level (up two, down one)
  typescript.relative_import_path("birch/handler/console", "birch/level")
  |> should.equal("../level.js")
}

pub fn relative_import_path_deep_to_root_test() {
  // birch/handler → _gleam (up one level)
  typescript.relative_import_path("birch/handler", "_gleam")
  |> should.equal("../_gleam.js")
}
