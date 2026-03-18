# talc

## Project Overview

An npm packaging tool for Gleam libraries, targeting the Erlang (BEAM) runtime. Reads a compiled
Gleam project and produces a publish-ready npm package directory with a generated `package.json`,
TypeScript `.d.ts` declarations, and workflow commands (`pack`, `publish`).

## Build Commands

```bash
gleam build              # Compile project
gleam test               # Run tests
gleam check              # Type check without building
gleam format src test    # Format code
gleam docs build         # Generate documentation
gleam run                # Run the CLI
```

## Just Commands

```bash
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format code
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks (format, check, test, build)
just pr           # Alias for ci (use before PR)
just main         # Extended checks for main branch
just clean        # Remove build artifacts
```

## Project Structure

```
src/
├── talc.gleam               # CLI entry point (glint commands: generate, check, pack, publish)
├── talc_interface_ffi.erl   # Erlang FFI: gleam export package-interface
├── talc_npm_ffi.erl         # Erlang FFI: npm pack/publish
└── talc/
    ├── gleam_toml.gleam     # gleam.toml parser → GleamConfig
    ├── talc_config.gleam    # talc.ccl parser → TalcConfig
    ├── package_json.gleam   # package.json generation with sub-path exports
    ├── output.gleam         # File I/O: write output dir, copy .mjs, write .d.ts
    ├── interface.gleam      # Package interface loader (gleam CLI → gleam_package_interface)
    ├── typescript.gleam     # Gleam Type → TypeScript type string mapper
    ├── dts.gleam            # .d.ts file emitter per module
    └── npm.gleam            # npm CLI wrapper (pack, publish, flag building)
test/
├── talc_test.gleam          # Test runner entry point
├── gleam_toml_test.gleam    # gleam.toml parsing tests
├── talc_config_test.gleam   # talc.ccl parsing tests
├── package_json_test.gleam  # JSON generation tests
├── typescript_test.gleam    # Type mapping tests
├── dts_test.gleam           # .d.ts emission tests
├── npm_test.gleam           # npm flag building tests
└── test_helpers.gleam       # Shared test utilities
```

## Architecture

### Module Organization

- **Main module** (`talc.gleam`): CLI entry point with `main` function
- **Submodules** (`talc/*.gleam`): Feature-specific implementations
- **Internal modules**: Mark with `internal_modules` in `gleam.toml`

### Error Handling

Use Result types for all fallible operations:

```gleam
pub fn parse(input: String) -> Result(Value, ParseError) {
  // ...
}
```

### Pattern Matching

Gleam enforces exhaustive pattern matching. Always handle all cases:

```gleam
case result {
  Ok(value) -> handle_success(value)
  Error(err) -> handle_error(err)
}
```

## Dependencies

### Runtime
- `gleam_stdlib` - Standard library
- `tom` - TOML parser (for gleam.toml)
- `ccl_test_runner` - CCL parser (for talc.ccl)
- `simplifile` - Filesystem operations
- `gleam_json` - JSON serialization
- `glint` - CLI framework
- `argv` - Cross-platform argument fetching
- `gleam_package_interface` - Decoder for Gleam compiler's package interface JSON

### Development
- `startest` - Testing framework

## Testing

Tests use `startest` framework:

```gleam
import startest/expect

pub fn example_test() {
  some_function()
  |> expect.to_equal(expected_value)
}
```

Run tests:
```bash
just test
# or
gleam test
```

## Tool Versions

Managed via `.tool-versions` (source of truth for CI):
- Erlang 27.2.1
- Gleam 1.14.0
- just 1.38.0

Local development can use `.mise.toml` for flexible versions.

## Conventions

- Use Result types over exceptions
- Exhaustive pattern matching
- Follow `gleam format` output
- Document public functions with `///` comments

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(parser): add support for nested objects
fix(validation): handle empty strings correctly
docs: update installation instructions
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
