/// Wrapper generation with Gleam native TypeScript metadata when available.
import gleam/list
import gleam/package_interface
import talc/native_types
import talc/wrapper

/// Generates wrapper files for one module using Gleam's native `.d.mts`
/// metadata when it can be read. Missing metadata is non-fatal for wrapped
/// modules and returns a warning alongside fallback generated wrapper types.
pub fn generate_module_wrapper_with_metadata(
  package_name: String,
  module_name: String,
  module: package_interface.Module,
) -> #(wrapper.WrapperResult, List(String)) {
  let fallback = wrapper.generate_module_wrapper(module, module_name)

  case fallback.has_wrapped_functions {
    False -> #(fallback, fallback.warnings)
    True ->
      case native_types.read_module(package_name, module_name) {
        Ok(module_types) -> {
          let result =
            wrapper.generate_module_wrapper_with_native(
              module,
              module_name,
              module_types,
            )
          #(result, result.warnings)
        }
        Error(error) -> {
          let warnings =
            list.append(
              [native_type_error_warning(module_name, error)],
              fallback.warnings,
            )
          #(wrapper.WrapperResult(..fallback, warnings: warnings), warnings)
        }
      }
  }
}

fn native_type_error_warning(
  module_name: String,
  error: native_types.NativeTypeError,
) -> String {
  case error {
    native_types.ReadError(path: path, detail: detail) ->
      "Missing native TypeScript metadata for module "
      <> module_name
      <> " at "
      <> path
      <> ": "
      <> detail
      <> "; falling back to generated types"
  }
}
