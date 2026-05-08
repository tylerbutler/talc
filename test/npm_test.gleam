import gleam/option
import startest/expect
import talc/npm

pub fn build_publish_flags_empty_test() {
  npm.build_publish_flags(False, Error(Nil), Error(Nil), False)
  |> expect.to_equal(Ok([]))
}

pub fn build_publish_flags_dry_run_test() {
  npm.build_publish_flags(True, Error(Nil), Error(Nil), False)
  |> expect.to_equal(Ok(["--dry-run"]))
}

pub fn build_publish_flags_tag_test() {
  npm.build_publish_flags(False, Ok("beta"), Error(Nil), False)
  |> expect.to_equal(Ok(["--tag", "beta"]))
}

pub fn build_publish_flags_access_test() {
  npm.build_publish_flags(False, Error(Nil), Ok("public"), False)
  |> expect.to_equal(Ok(["--access", "public"]))
}

pub fn build_publish_flags_provenance_test() {
  npm.build_publish_flags(False, Error(Nil), Error(Nil), True)
  |> expect.to_equal(Ok(["--provenance"]))
}

pub fn build_publish_flags_all_test() {
  npm.build_publish_flags(True, Ok("next"), Ok("restricted"), True)
  |> expect.to_equal(
    Ok(["--provenance", "--access", "restricted", "--tag", "next", "--dry-run"]),
  )
}

pub fn build_publish_flags_invalid_tag_test() {
  npm.build_publish_flags(False, Ok("latest; echo pwned"), Error(Nil), False)
  |> expect.to_equal(Error(npm.InvalidTag("latest; echo pwned")))
}

pub fn build_publish_flags_invalid_access_test() {
  npm.build_publish_flags(False, Error(Nil), Ok("public; echo pwned"), False)
  |> expect.to_equal(Error(npm.InvalidAccess("public; echo pwned")))
}

pub fn build_publish_flags_safe_values_test() {
  npm.build_publish_flags(False, Ok("beta-1"), Ok("public"), True)
  |> expect.to_equal(
    Ok(["--provenance", "--access", "public", "--tag", "beta-1"]),
  )
}

pub fn error_to_string_failed_test() {
  npm.NpmFailed("publish", 1, "auth required\n")
  |> npm.error_to_string()
  |> expect.to_equal("npm publish failed (exit code 1):\nauth required")
}

pub fn error_to_string_timeout_test() {
  npm.NpmTimeout("pack")
  |> npm.error_to_string()
  |> expect.to_equal("npm pack timed out")
}

pub fn error_to_string_not_found_test() {
  npm.NpmNotFound
  |> npm.error_to_string()
  |> expect.to_equal("npm executable not found")
}

pub fn build_publish_flags_empty_tag_test() {
  npm.build_publish_flags(False, Ok(""), Error(Nil), False)
  |> expect.to_equal(Error(npm.InvalidTag("")))
}

pub fn build_publish_flags_tag_with_spaces_test() {
  npm.build_publish_flags(False, Ok("latest beta"), Error(Nil), False)
  |> expect.to_equal(Error(npm.InvalidTag("latest beta")))
}

pub fn build_publish_flags_access_private_test() {
  npm.build_publish_flags(False, Error(Nil), Ok("private"), False)
  |> expect.to_equal(Error(npm.InvalidAccess("private")))
}

pub fn build_publish_flags_both_invalid_tag_wins_test() {
  npm.build_publish_flags(False, Ok("bad tag!"), Ok("private"), False)
  |> expect.to_equal(Error(npm.InvalidTag("bad tag!")))
}

// -- build_registry_flags tests --

pub fn build_registry_flags_no_registry_test() {
  npm.build_registry_flags(option.None, [])
  |> expect.to_equal(Ok([]))
}

pub fn build_registry_flags_with_registry_test() {
  npm.build_registry_flags(option.Some("https://registry.example.com"), [])
  |> expect.to_equal(Ok(["--registry", "https://registry.example.com"]))
}

pub fn build_registry_flags_publishconfig_override_test() {
  npm.build_registry_flags(option.Some("https://registry.example.com"), [
    "publishConfig",
  ])
  |> expect.to_equal(Ok([]))
}

pub fn build_registry_flags_empty_url_test() {
  npm.build_registry_flags(option.Some(""), [])
  |> expect.to_equal(Error("Registry URL must not be empty"))
}

pub fn build_registry_flags_other_extra_fields_no_override_test() {
  npm.build_registry_flags(option.Some("https://npm.pkg.github.com"), [
    "license",
    "author",
  ])
  |> expect.to_equal(Ok(["--registry", "https://npm.pkg.github.com"]))
}
