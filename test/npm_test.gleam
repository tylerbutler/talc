import startest/expect
import talc/npm

pub fn build_publish_flags_empty_test() {
  npm.build_publish_flags(False, Error(Nil), Error(Nil), False)
  |> expect.to_equal([])
}

pub fn build_publish_flags_dry_run_test() {
  npm.build_publish_flags(True, Error(Nil), Error(Nil), False)
  |> expect.to_equal(["--dry-run"])
}

pub fn build_publish_flags_tag_test() {
  npm.build_publish_flags(False, Ok("beta"), Error(Nil), False)
  |> expect.to_equal(["--tag", "beta"])
}

pub fn build_publish_flags_access_test() {
  npm.build_publish_flags(False, Error(Nil), Ok("public"), False)
  |> expect.to_equal(["--access", "public"])
}

pub fn build_publish_flags_provenance_test() {
  npm.build_publish_flags(False, Error(Nil), Error(Nil), True)
  |> expect.to_equal(["--provenance"])
}

pub fn build_publish_flags_all_test() {
  npm.build_publish_flags(True, Ok("next"), Ok("restricted"), True)
  |> expect.to_equal([
    "--provenance", "--access", "restricted", "--tag", "next", "--dry-run",
  ])
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
