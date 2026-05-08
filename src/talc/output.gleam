/// File output operations for npm package generation.
///
/// This module handles creating the output directory structure,
/// writing generated files, and copying source artifacts.
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile

/// Errors that can occur during output operations.
pub type OutputError {
  WriteError(path: String, detail: String)
  CopyError(src: String, dest: String, detail: String)
  DirectoryError(path: String, detail: String)
  BuildNotFound(path: String)
  /// Output directory is absolute or contains `..` traversal components.
  UnsafeOutputDir(path: String)
  /// A required build artifact is absent.
  MissingArtifact(src: String, dest: String)
}

/// Formats an OutputError as a human-readable string.
pub fn error_to_string(error: OutputError) -> String {
  case error {
    WriteError(path, detail) -> "Failed to write " <> path <> ": " <> detail
    CopyError(src, _dest, detail) -> "Failed to copy " <> src <> ": " <> detail
    DirectoryError(path, detail) ->
      "Failed to create directory " <> path <> ": " <> detail
    BuildNotFound(path) ->
      "Build output not found at "
      <> path
      <> ". Run `gleam build --target javascript` first."
    UnsafeOutputDir(path) ->
      "Unsafe output directory: "
      <> path
      <> ". Use a relative path with no '..' components."
    MissingArtifact(src, dest) ->
      "Required build artifact missing: "
      <> src
      <> " (expected at "
      <> dest
      <> ")"
  }
}

/// Validates that an output directory path is safe to use.
///
/// Rejects absolute paths, empty strings, and any path that contains `..` components,
/// including trailing ones like `foo/..` or `a/b/..`.
pub fn validate_output_dir(path: String) -> Result(Nil, OutputError) {
  let is_empty = string.is_empty(path)
  let is_absolute = string.starts_with(path, "/")
  let has_dotdot =
    string.split(path, "/")
    |> list.any(fn(component) { component == ".." })
  case is_empty || is_absolute || has_dotdot {
    True -> Error(UnsafeOutputDir(path))
    False -> Ok(Nil)
  }
}

/// Creates the output directory structure and writes all output files.
///
/// Copies `.mjs` and `.d.mts` files from the Gleam build output. When
/// `public_modules` is `Some(list)`, only files for those modules are copied.
/// When `None`, all files are copied.
///
/// `generated_files` is a list of `#(relative_path, content)` pairs for
/// files to write (e.g., wrapper modules).
pub fn write(
  output_dir: String,
  package_name: String,
  package_json: String,
  public_modules: Option(List(String)),
  generated_files: List(#(String, String)),
) -> Result(List(String), OutputError) {
  use _ <- try_result(validate_output_dir(output_dir))

  let dist_dir = output_dir <> "/dist"
  let build_dir = "build/dev/javascript/" <> package_name
  let build_parent = "build/dev/javascript"

  // Create directories
  use _ <- try_result(
    simplifile.create_directory_all(dist_dir)
    |> map_file_error(DirectoryError(dist_dir, _)),
  )

  // Write package.json
  let package_json_path = output_dir <> "/package.json"
  use _ <- try_result(
    simplifile.write(to: package_json_path, contents: package_json)
    |> map_file_error(WriteError(package_json_path, _)),
  )
  let written = [package_json_path]

  // Copy .mjs and .d.mts files from build output
  use build_files <- try_result(copy_build_files(
    build_dir,
    dist_dir,
    package_name,
    public_modules,
  ))

  // Copy prelude support files (prelude.mjs, prelude.d.mts)
  use prelude_files <- try_result(copy_prelude_files(build_parent, dist_dir))

  // Write generated files (e.g., wrapper modules)
  use gen_written <- try_result(write_generated_files(dist_dir, generated_files))

  // Copy optional files (README.md, LICENSE)
  let optional_files = copy_optional_files(output_dir)

  Ok(
    list.flatten([
      written,
      build_files,
      prelude_files,
      gen_written,
      optional_files,
    ]),
  )
}

/// Copies .mjs and .d.mts files from the Gleam build output to dist/.
/// If public_modules is Some, only copies files for those modules plus
/// the gleam.mjs/gleam.d.mts support files.
fn copy_build_files(
  build_dir: String,
  dist_dir: String,
  package_name: String,
  public_modules: Option(List(String)),
) -> Result(List(String), OutputError) {
  case simplifile.is_directory(build_dir) {
    Ok(True) -> {
      case public_modules {
        None ->
          copy_dir_recursive_multi(build_dir, dist_dir, [".mjs", ".d.mts"])
        Some(modules) ->
          copy_module_files(build_dir, dist_dir, package_name, modules)
      }
    }
    _ -> Error(BuildNotFound(build_dir))
  }
}

/// Copies .mjs and .d.mts files for specific modules plus gleam support files.
/// Both artifacts are required; missing files return `MissingArtifact`.
fn copy_module_files(
  build_dir: String,
  dist_dir: String,
  _package_name: String,
  modules: List(String),
) -> Result(List(String), OutputError) {
  // Copy module files (.mjs + .d.mts); both are required
  use module_files_rev <- try_result(
    list.try_fold(modules, [], fn(acc, module_name) {
      let extensions = [".mjs", ".d.mts"]
      list.try_fold(extensions, acc, fn(inner_acc, ext) {
        let src = build_dir <> "/" <> module_name <> ext
        let dest = dist_dir <> "/" <> module_name <> ext
        case simplifile.is_file(src) {
          Ok(True) -> {
            let dest_dir = string_before_last(dest, "/")
            use _ <- try_result(
              simplifile.create_directory_all(dest_dir)
              |> map_file_error(DirectoryError(dest_dir, _)),
            )
            use _ <- try_result(
              simplifile.copy_file(at: src, to: dest)
              |> map_file_error(CopyError(src, dest, _)),
            )
            Ok([dest, ..inner_acc])
          }
          _ -> Error(MissingArtifact(src, dest))
        }
      })
    }),
  )

  // Copy gleam.mjs and gleam.d.mts support files; both are required
  use gleam_files_rev <- try_result(
    list.try_fold(["gleam.mjs", "gleam.d.mts"], [], fn(acc, file) {
      let src = build_dir <> "/" <> file
      let dest = dist_dir <> "/" <> file
      case simplifile.is_file(src) {
        Ok(True) -> {
          use _ <- try_result(
            simplifile.copy_file(at: src, to: dest)
            |> map_file_error(CopyError(src, dest, _)),
          )
          Ok([dest, ..acc])
        }
        _ -> Error(MissingArtifact(src, dest))
      }
    }),
  )

  Ok(list.append(list.reverse(module_files_rev), list.reverse(gleam_files_rev)))
}

/// Copies prelude.mjs and prelude.d.mts from the build parent directory.
/// These are needed because gleam.d.mts re-exports from ../prelude.d.mts.
/// Both files are required; missing files return `MissingArtifact`.
fn copy_prelude_files(
  build_parent: String,
  dist_dir: String,
) -> Result(List(String), OutputError) {
  use files_rev <- try_result(
    list.try_fold(["prelude.mjs", "prelude.d.mts"], [], fn(acc, file) {
      let src = build_parent <> "/" <> file
      // Place prelude one level up from dist so ../prelude.d.mts resolves
      let dest = dist_dir <> "/../" <> file
      case simplifile.is_file(src) {
        Ok(True) -> {
          use _ <- try_result(
            simplifile.copy_file(at: src, to: dest)
            |> map_file_error(CopyError(src, dest, _)),
          )
          Ok([dest, ..acc])
        }
        _ -> Error(MissingArtifact(src, dest))
      }
    }),
  )
  Ok(list.reverse(files_rev))
}

/// Writes generated files to the dist directory.
fn write_generated_files(
  dist_dir: String,
  files: List(#(String, String)),
) -> Result(List(String), OutputError) {
  use files_rev <- try_result(
    list.try_fold(files, [], fn(acc, pair) {
      let #(rel_path, content) = pair
      let dest = dist_dir <> "/" <> rel_path
      let dest_dir = string_before_last(dest, "/")
      use _ <- try_result(
        simplifile.create_directory_all(dest_dir)
        |> map_file_error(DirectoryError(dest_dir, _)),
      )
      use _ <- try_result(
        simplifile.write(to: dest, contents: content)
        |> map_file_error(WriteError(dest, _)),
      )
      Ok([dest, ..acc])
    }),
  )
  Ok(list.reverse(files_rev))
}

/// Recursively copies files matching any of the given extensions.
fn copy_dir_recursive_multi(
  src_dir: String,
  dest_dir: String,
  extensions: List(String),
) -> Result(List(String), OutputError) {
  use _ <- try_result(
    simplifile.create_directory_all(dest_dir)
    |> map_file_error(DirectoryError(dest_dir, _)),
  )
  use entries <- try_result(
    simplifile.read_directory(src_dir)
    |> map_file_error(DirectoryError(src_dir, _)),
  )

  use files_rev <- try_result(
    list.try_fold(entries, [], fn(acc, entry) {
      let src_path = src_dir <> "/" <> entry
      let dest_path = dest_dir <> "/" <> entry
      case simplifile.is_directory(src_path) {
        Ok(True) -> {
          use sub_files <- try_result(copy_dir_recursive_multi(
            src_path,
            dest_path,
            extensions,
          ))
          Ok(list.fold(sub_files, acc, fn(a, f) { [f, ..a] }))
        }
        _ -> {
          let matches =
            list.any(extensions, fn(ext) { string.ends_with(entry, ext) })
          case matches {
            True -> {
              use _ <- try_result(
                simplifile.copy_file(at: src_path, to: dest_path)
                |> map_file_error(CopyError(src_path, dest_path, _)),
              )
              Ok([dest_path, ..acc])
            }
            False -> Ok(acc)
          }
        }
      }
    }),
  )
  Ok(list.reverse(files_rev))
}

/// Copies README.md and LICENSE from the project root if they exist.
fn copy_optional_files(output_dir: String) -> List(String) {
  ["README.md", "LICENSE"]
  |> list.filter_map(fn(file) {
    case simplifile.is_file(file) {
      Ok(True) -> {
        let dest = output_dir <> "/" <> file
        case simplifile.copy_file(at: file, to: dest) {
          Ok(_) -> Ok(dest)
          Error(_) -> Error(Nil)
        }
      }
      _ -> Error(Nil)
    }
  })
}

// Helper to chain Result operations
fn try_result(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

fn map_file_error(
  result: Result(a, simplifile.FileError),
  to_error: fn(String) -> OutputError,
) -> Result(a, OutputError) {
  case result {
    Ok(value) -> Ok(value)
    Error(err) -> Error(to_error(file_error_to_string(err)))
  }
}

fn file_error_to_string(error: simplifile.FileError) -> String {
  case error {
    simplifile.Enoent -> "file not found"
    simplifile.Eacces -> "permission denied"
    simplifile.Eexist -> "already exists"
    simplifile.Enotdir -> "not a directory"
    simplifile.Eisdir -> "is a directory"
    simplifile.Enospc -> "no space left on device"
    _ -> "file system error"
  }
}

/// Returns the portion of a string before the last occurrence of a separator.
fn string_before_last(s: String, sep: String) -> String {
  case string.split(s, sep) {
    [] -> s
    [only] -> only
    parts -> {
      let assert [_, ..rest] = list.reverse(parts)
      list.reverse(rest) |> string.join(sep)
    }
  }
}
