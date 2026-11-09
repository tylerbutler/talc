import startest/expect
import talc/interface

pub fn interface_error_messages_preserve_failure_reason_test() {
  interface.error_to_string(interface.NotFound)
  |> expect.string_to_contain("not found in PATH")
  interface.error_to_string(interface.TimedOut)
  |> expect.string_to_contain("Timed out")
  interface.error_to_string(interface.CommandFailed(37, "compiler diagnostic"))
  |> expect.string_to_contain("exit code 37:\ncompiler diagnostic")
  interface.error_to_string(interface.ReadFailed(
    "output.json",
    "permission denied",
  ))
  |> expect.string_to_contain("output.json: permission denied")
  interface.error_to_string(interface.DecodeFailed("unexpected byte"))
  |> expect.string_to_contain("JSON: unexpected byte")
}
