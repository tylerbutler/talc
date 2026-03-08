/// File output operations for npm package generation.
///
/// This module handles creating the output directory structure,
/// writing generated files, and copying source artifacts.
import gleam/list
import gleam/string
import simplifile

/// Errors that can occur during output operations.
pub type OutputError {
  WriteError(path: String, detail: String)
  CopyError(src: String, dest: String, detail: String)
  DirectoryError(path: String, detail: String)
  BuildNotFound(path: String)
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
  }
}

/// Creates the output directory structure and writes all output files.
///
/// The output structure is:
/// ```
/// {output_dir}/
/// ├── package.json
/// ├── README.md        (copied if present)
/// ├── LICENSE           (copied if present)
/// └── dist/
///     └── {name}.mjs   (copied from build output)
/// ```
pub fn write(
  output_dir: String,
  package_name: String,
  package_json: String,
) -> Result(List(String), OutputError) {
  let dist_dir = output_dir <> "/dist"
  let build_dir = "build/dev/javascript/" <> package_name

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

  // Copy .mjs files from build output
  use mjs_files <- try_result(copy_mjs_files(build_dir, dist_dir))

  // Copy optional files (README.md, LICENSE)
  let optional_files = copy_optional_files(output_dir)

  Ok(list.flatten([written, mjs_files, optional_files]))
}

/// Copies the compiled JS build directory to dist/, preserving structure.
fn copy_mjs_files(
  build_dir: String,
  dist_dir: String,
) -> Result(List(String), OutputError) {
  case simplifile.is_directory(build_dir) {
    Ok(True) -> copy_dir_recursive(build_dir, dist_dir, ".mjs")
    _ -> Error(BuildNotFound(build_dir))
  }
}

/// Recursively copies files matching the given extension from src to dest.
fn copy_dir_recursive(
  src_dir: String,
  dest_dir: String,
  extension: String,
) -> Result(List(String), OutputError) {
  use _ <- try_result(
    simplifile.create_directory_all(dest_dir)
    |> map_file_error(DirectoryError(dest_dir, _)),
  )
  use entries <- try_result(case simplifile.read_directory(src_dir) {
    Ok(e) -> Ok(e)
    Error(_) -> Ok([])
  })

  list.try_fold(entries, [], fn(acc, entry) {
    let src_path = src_dir <> "/" <> entry
    let dest_path = dest_dir <> "/" <> entry
    case simplifile.is_directory(src_path) {
      Ok(True) -> {
        use sub_files <- try_result(copy_dir_recursive(
          src_path,
          dest_path,
          extension,
        ))
        Ok(list.append(acc, sub_files))
      }
      _ -> {
        case string.ends_with(entry, extension) {
          True -> {
            use _ <- try_result(
              simplifile.copy_file(at: src_path, to: dest_path)
              |> map_file_error(CopyError(src_path, dest_path, _)),
            )
            Ok(list.append(acc, [dest_path]))
          }
          False -> Ok(acc)
        }
      }
    }
  })
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
fn try_result(result: Result(a, e), next: fn(a) -> Result(b, e)) -> Result(b, e) {
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
