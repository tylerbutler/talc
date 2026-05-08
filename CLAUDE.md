# talc

## Project Overview

An npm packaging tool for Gleam libraries. Runs on Erlang/BEAM. Reads Gleam JavaScript build
output (`build/dev/javascript`) and produces a publish-ready npm package directory with a
generated `package.json`, Gleam's native `.d.mts` type declarations, and optional true-myth
wrapper modules for Result/Option types. Provides workflow commands (`pack`, `publish`).

### Type Strategy

talc uses Gleam's own `.d.mts` files (generated via `[javascript] typescript_declarations = true`
in `gleam.toml`) as the source of truth for TypeScript types. These are always correct because
the same compiler produces both the `.mjs` and `.d.mts` files.

When `use_true_myth = true` (the default), talc generates thin wrapper modules that convert
top-level `Result` and `Option` types to `true-myth` `Result` and `Maybe` types, providing
a more ergonomic API for TypeScript consumers. The `true-myth` package is automatically added
as a peer dependency.

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
just ci           # Run all CI checks (format, check, test, build, integration)
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
    ├── talc_config.gleam    # talc.ccl parser → TalcConfig (includes use_true_myth option)
    ├── package_json.gleam   # package.json generation with sub-path exports
    ├── output.gleam         # File I/O: write output dir, copy .mjs/.d.mts, write wrappers
    ├── interface.gleam      # Package interface loader (gleam CLI → gleam_package_interface)
    ├── wrapper.gleam        # true-myth wrapper .mjs/.d.ts generator for Result/Option
    └── npm.gleam            # npm CLI wrapper (pack, publish, flag building)
test/
├── talc_test.gleam          # Test runner entry point
├── gleam_toml_test.gleam    # gleam.toml parsing tests
├── talc_config_test.gleam   # talc.ccl parsing tests (includes use_true_myth)
├── package_json_test.gleam  # JSON generation tests
├── output_test.gleam        # Output directory and artifact copy tests
├── wrapper_test.gleam       # true-myth wrapper generation tests
├── npm_test.gleam           # npm flag building tests
├── fixtures/                # Integration fixture projects
│   └── basic_gleam_package/ # Used by just test-integration
└── integration/             # Node.js integration verifiers
    └── verify-package.mjs
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
- `ccl` - CCL parser (for talc.ccl)
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
