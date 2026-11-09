/// File output operations for npm package generation.
///
/// This module handles creating the output directory structure,
/// writing generated files, and copying source artifacts.
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
  /// An output path contains a symbolic link or a multiply linked file.
  UnsafeFilesystemPath(path: String)
  /// Output contains artifacts that are absent from this generation.
  StaleOutput(path: String)
  InspectError(path: String, detail: String)
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
      <> ". Use a non-root relative path with forward slashes, no drive prefix, and no '..' components."
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
    UnsafeFilesystemPath(path) ->
      "Unsafe filesystem path: "
      <> path
      <> ". Use output without symbolic links or multiply linked files."
    StaleOutput(path) ->
      "Obsolete package artifact found at "
      <> path
      <> ". Choose a fresh output directory before generating; no files were deleted."
    InspectError(path, detail) -> "Failed to inspect " <> path <> ": " <> detail
  }
}

/// Validates that an output directory path is safe to use.
///
/// Uses portable forward-slash paths. Rejects absolute paths, Windows path
/// forms, parent traversal, and aliases of the project root.
pub fn validate_output_dir(path: String) -> Result(Nil, OutputError) {
  let components = string.split(path, "/")
  let unsafe_component =
    list.any(components, fn(component) {
      component == ".."
      || { component != "." && string.ends_with(component, ".") }
      || string.ends_with(component, " ")
    })
  let is_root =
    list.all(components, fn(component) { component == "" || component == "." })
  case
    string.is_empty(path)
    || string.starts_with(path, "/")
    || string.contains(path, "\\")
    || string.contains(path, ":")
    || string.contains(path, "\u{0}")
    || unsafe_component
    || is_root
  {
    True -> Error(UnsafeOutputDir(path))
    False -> Ok(Nil)
  }
}

fn inspect(path: String) -> Result(Option(simplifile.FileType), OutputError) {
  case simplifile.link_info(path) {
    Ok(info) ->
      case simplifile.file_info_type(info) {
        simplifile.Symlink -> Error(UnsafeFilesystemPath(path))
        simplifile.File if info.nlinks > 1 -> Error(UnsafeFilesystemPath(path))
        kind -> Ok(Some(kind))
      }
    Error(simplifile.Enoent) -> Ok(None)
    Error(error) -> Error(InspectError(path, simplifile.describe_error(error)))
  }
}

fn validate_ancestors(path: String) -> Result(Nil, OutputError) {
  use _ <- result.try(
    string.split(path, "/")
    |> list.try_fold("", fn(parent, component) {
      let current = case parent {
        "" -> component
        _ -> parent <> "/" <> component
      }
      use _ <- result.try(inspect(current))
      Ok(current)
    }),
  )
  Ok(Nil)
}

/// Lists regular files without following links, including dangling links.
fn scan_files(directory: String) -> Result(List(String), OutputError) {
  use kind <- result.try(inspect(directory))
  case kind {
    None -> Ok([])
    Some(simplifile.Directory) -> {
      use entries <- result.try(
        simplifile.read_directory(directory)
        |> map_file_error(InspectError(directory, _)),
      )
      use nested <- result.try(
        list.try_map(entries, fn(entry) {
          scan_files(directory <> "/" <> entry)
        }),
      )
      Ok(list.flatten(nested))
    }
    Some(simplifile.File) -> Ok([directory])
    Some(_) ->
      Error(InspectError(directory, "expected a regular file or directory"))
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
  use _ <- try_result(validate_output_dir(package_name))
  use _ <- try_result(case string.contains(package_name, "/") {
    True -> Error(UnsafeOutputDir(package_name))
    False -> Ok(Nil)
  })
  use _ <- try_result(validate_ancestors(output_dir))
  use existing_files <- try_result(scan_files(output_dir))

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

  use _ <- try_result(validate_ancestors(build_dir))
  use kind <- try_result(inspect(build_dir))
  use _ <- try_result(case kind {
    Some(simplifile.Directory) -> Ok(Nil)
    _ -> Error(BuildNotFound(build_dir))
  })
  use _ <- try_result(case public_modules {
    None -> Ok(Nil)
    Some(modules) ->
      validate_module_files(build_dir, dist_dir, ["gleam", ..modules])
  })
  use build_files <- try_result(plan_artifacts(build_dir, dist_dir))
  use prelude_files <- try_result(
    list.try_map(["prelude.mjs", "prelude.d.mts"], fn(file) {
      let src = build_parent <> "/" <> file
      let dest = output_dir <> "/" <> file
      use _ <- result.try(require_file(src, dest))
      Ok(#(src, dest))
    }),
  )
  use entries <- try_result(
    simplifile.read_directory(build_parent)
    |> map_file_error(InspectError(build_parent, _)),
  )
  use dependencies <- try_result(
    list.try_map(entries, fn(entry) {
      let src = build_parent <> "/" <> entry
      use kind <- result.try(inspect(src))
      case kind, entry == package_name {
        Some(simplifile.Directory), False ->
          plan_artifacts(src, output_dir <> "/" <> entry)
        _, _ -> Ok([])
      }
    }),
  )
  use optional_files <- try_result(plan_optional_files(output_dir))
  let copies =
    list.flatten([
      build_files,
      prelude_files,
      list.flatten(dependencies),
      optional_files,
    ])
  let package_json_path = output_dir <> "/package.json"
  let expected = [package_json_path, ..list.map(copies, fn(copy) { copy.1 })]
  use _ <- try_result(
    list.try_each(existing_files, fn(file) {
      case is_package_artifact(file) && !list.contains(expected, file) {
        True -> Error(StaleOutput(file))
        False -> Ok(Nil)
      }
    }),
  )
  use _ <- try_result(
    list.try_each(expected, fn(path) {
      use _ <- result.try(validate_output_dir(path))
      use _ <- result.try(validate_ancestors(path))
      use kind <- result.try(inspect(path))
      case kind {
        None | Some(simplifile.File) -> Ok(Nil)
        Some(_) -> Error(InspectError(path, "expected a regular file"))
      }
    }),
  )
  use _ <- try_result(
    list.try_each(copies, fn(copy) {
      use _ <- result.try(prepare_destination(copy.1))
      simplifile.copy_file(at: copy.0, to: copy.1)
      |> map_file_error(CopyError(copy.0, copy.1, _))
    }),
  )
  use _ <- try_result(prepare_destination(package_json_path))
  use _ <- try_result(
    simplifile.write(to: package_json_path, contents: package_json)
    |> map_file_error(WriteError(package_json_path, _)),
  )
  Ok(expected)
}

fn prepare_destination(path: String) -> Result(Nil, OutputError) {
  use _ <- result.try(validate_ancestors(path))
  let parent =
    path
    |> string.split("/")
    |> list.reverse
    |> list.drop(1)
    |> list.reverse
    |> string.join("/")
  simplifile.create_directory_all(parent)
  |> map_file_error(DirectoryError(parent, _))
}

const artifact_extensions = [".mjs", ".js", ".d.mts", ".d.ts"]

const optional_assets = ["README.md", "LICENSE", "LICENSE-MIT", "LICENSE-APACHE"]

fn is_package_artifact(path: String) -> Bool {
  list.any(artifact_extensions, fn(ext) { string.ends_with(path, ext) })
  || list.any(optional_assets, fn(file) { string.ends_with(path, "/" <> file) })
}

/// Checks artifacts for public modules and the Gleam support module.
/// Both artifacts are required; missing files return `MissingArtifact`.
fn validate_module_files(
  build_dir: String,
  dist_dir: String,
  modules: List(String),
) -> Result(Nil, OutputError) {
  list.try_fold(modules, Nil, fn(_, module_name) {
    use _ <- result.try(validate_output_dir(module_name))
    list.try_fold([".mjs", ".d.mts"], Nil, fn(_, ext) {
      let src = build_dir <> "/" <> module_name <> ext
      let dest = dist_dir <> "/" <> module_name <> ext
      require_file(src, dest)
    })
  })
}

fn require_file(src: String, dest: String) -> Result(Nil, OutputError) {
  use _ <- result.try(validate_ancestors(src))
  use kind <- result.try(inspect(src))
  case kind {
    Some(simplifile.File) -> Ok(Nil)
    None -> Error(MissingArtifact(src, dest))
    Some(_) -> Error(InspectError(src, "expected a regular file"))
  }
}

fn plan_artifacts(
  src_dir: String,
  dest_dir: String,
) -> Result(List(#(String, String)), OutputError) {
  use files <- result.try(scan_files(src_dir))
  files
  |> list.filter(fn(path) {
    list.any(artifact_extensions, fn(ext) { string.ends_with(path, ext) })
  })
  |> list.try_map(fn(src) {
    let relative = string.drop_start(src, string.length(src_dir) + 1)
    use _ <- result.try(validate_output_dir(relative))
    Ok(#(src, dest_dir <> "/" <> relative))
  })
}

fn plan_optional_files(
  output_dir: String,
) -> Result(List(#(String, String)), OutputError) {
  use files <- result.try(
    list.try_map(optional_assets, fn(file) {
      use kind <- result.try(inspect(file))
      case kind {
        None -> Ok([])
        Some(simplifile.File) -> Ok([#(file, output_dir <> "/" <> file)])
        Some(_) -> Error(InspectError(file, "expected a regular file"))
      }
    }),
  )
  Ok(list.flatten(files))
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
  simplifile.describe_error(error)
}
