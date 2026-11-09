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
  /// An output directory still contains wrappers from an earlier generation.
  ExistingWrappers(path: String)
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
    ExistingWrappers(path) ->
      "Legacy wrapper output found at "
      <> path
      <> ". Remove it or choose a fresh output directory before generating."
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
/// Copies JavaScript and declarations, including private modules and FFI.
/// When `public_modules` is `Some(list)`, checks that those modules and the
/// Gleam support module have both `.mjs` and `.d.mts` files.
pub fn write(
  output_dir: String,
  package_name: String,
  package_json: String,
  public_modules: Option(List(String)),
) -> Result(List(String), OutputError) {
  use _ <- try_result(validate_output_dir(output_dir))

  let dist_dir = output_dir <> "/dist"
  let build_dir = "build/dev/javascript/" <> package_name
  let build_parent = "build/dev/javascript"

  let legacy_dir = dist_dir <> "/_wrapper"
  use _ <- try_result(case simplifile.is_directory(legacy_dir) {
    Ok(True) -> Error(ExistingWrappers(legacy_dir))
    Ok(False) | Error(simplifile.Enoent) -> Ok(Nil)
    Error(error) ->
      Error(DirectoryError(legacy_dir, file_error_to_string(error)))
  })

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
    public_modules,
  ))

  // Copy prelude support files (prelude.mjs, prelude.d.mts)
  use prelude_files <- try_result(copy_prelude_files(build_parent, dist_dir))

  // Copy dependency JavaScript artifacts that compiled modules import via
  // paths like ../gleam_stdlib/...
  use dependency_files <- try_result(copy_dependency_files(
    build_parent,
    output_dir,
    package_name,
  ))

  // Copy optional files (README.md, LICENSE)
  let optional_files = copy_optional_files(output_dir)

  Ok(
    list.flatten([
      written,
      build_files,
      prelude_files,
      dependency_files,
      optional_files,
    ]),
  )
}

/// Copies build artifacts without changing their relative import paths.
fn copy_build_files(
  build_dir: String,
  dist_dir: String,
  public_modules: Option(List(String)),
) -> Result(List(String), OutputError) {
  case simplifile.is_directory(build_dir) {
    Ok(True) -> {
      use _ <- try_result(case public_modules {
        None -> Ok(Nil)
        Some(modules) ->
          validate_module_files(build_dir, dist_dir, ["gleam", ..modules])
      })
      copy_dir_recursive_multi(build_dir, dist_dir, artifact_extensions)
    }
    _ -> Error(BuildNotFound(build_dir))
  }
}

const artifact_extensions = [".mjs", ".js", ".d.mts", ".d.ts"]

/// Checks artifacts for public modules and the Gleam support module.
/// Both artifacts are required; missing files return `MissingArtifact`.
fn validate_module_files(
  build_dir: String,
  dist_dir: String,
  modules: List(String),
) -> Result(Nil, OutputError) {
  list.try_fold(modules, Nil, fn(_, module_name) {
    list.try_fold([".mjs", ".d.mts"], Nil, fn(_, ext) {
      let src = build_dir <> "/" <> module_name <> ext
      let dest = dist_dir <> "/" <> module_name <> ext
      case simplifile.is_file(src) {
        Ok(True) -> Ok(Nil)
        _ -> Error(MissingArtifact(src, dest))
      }
    })
  })
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

/// Copies dependency package `.mjs` and `.d.mts` artifacts next to `dist/`.
///
/// Gleam's JavaScript output uses relative imports such as
/// `../gleam_stdlib/gleam/int.mjs`, so dependency artifacts must be present at
/// the package root for generated modules to run in Node.
fn copy_dependency_files(
  build_parent: String,
  output_dir: String,
  package_name: String,
) -> Result(List(String), OutputError) {
  use entries <- try_result(
    simplifile.read_directory(build_parent)
    |> map_file_error(DirectoryError(build_parent, _)),
  )

  use files_rev <- try_result(
    list.try_fold(entries, [], fn(acc, entry) {
      let src = build_parent <> "/" <> entry
      let dest = output_dir <> "/" <> entry
      case entry == package_name {
        True -> Ok(acc)
        False ->
          case simplifile.is_directory(src) {
            Ok(True) -> {
              use copied <- try_result(copy_dir_recursive_multi(
                src,
                dest,
                artifact_extensions,
              ))
              Ok(list.fold(copied, acc, fn(a, f) { [f, ..a] }))
            }
            _ -> Ok(acc)
          }
      }
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
