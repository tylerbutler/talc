import gleeunit/should
import talc/npm

pub fn build_publish_flags_empty_test() {
  npm.build_publish_flags(False, Error(Nil), Error(Nil), False)
  |> should.equal([])
}

pub fn build_publish_flags_dry_run_test() {
  npm.build_publish_flags(True, Error(Nil), Error(Nil), False)
  |> should.equal(["--dry-run"])
}

pub fn build_publish_flags_tag_test() {
  npm.build_publish_flags(False, Ok("beta"), Error(Nil), False)
  |> should.equal(["--tag", "beta"])
}

pub fn build_publish_flags_access_test() {
  npm.build_publish_flags(False, Error(Nil), Ok("public"), False)
  |> should.equal(["--access", "public"])
}

pub fn build_publish_flags_provenance_test() {
  npm.build_publish_flags(False, Error(Nil), Error(Nil), True)
  |> should.equal(["--provenance"])
}

pub fn build_publish_flags_all_test() {
  npm.build_publish_flags(True, Ok("next"), Ok("restricted"), True)
  |> should.equal([
    "--provenance", "--access", "restricted", "--tag", "next", "--dry-run",
  ])
}

pub fn error_to_string_failed_test() {
  npm.NpmFailed("publish", 1, "auth required\n")
  |> npm.error_to_string()
  |> should.equal("npm publish failed (exit code 1):\nauth required")
}

pub fn error_to_string_timeout_test() {
  npm.NpmTimeout("pack")
  |> npm.error_to_string()
  |> should.equal("npm pack timed out")
}
