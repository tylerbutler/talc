# Gleam Project Tasks

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias d := docs
alias cl := change

default:
    @just --list

# === DEPENDENCIES ===

# Download project dependencies
deps:
    gleam deps download

# === BUILD ===

# Build project (Erlang target)
build:
    gleam build

# Build with warnings as errors
build-strict:
    gleam build --warnings-as-errors

# === TESTING ===

# Run all tests
test:
    gleam test

# Run fixture-based JavaScript/npm packaging integration test
test-integration:
    bash -euo pipefail -c 'fixture="test/fixtures/basic_gleam_package"; cleanup() { rm -rf "$fixture/build" "$fixture/npm_dist" "$fixture/node_modules" "$fixture/package-lock.json" "$fixture/manifest.toml"; }; cleanup; trap cleanup EXIT; gleam build --no-print-progress; (cd "$fixture" && gleam deps download && gleam build --target javascript); erl -noshell -pa "$PWD"/build/dev/erlang/*/ebin -eval '\''file:set_cwd("test/fixtures/basic_gleam_package"), talc:main(), halt().'\'' -extra generate; npm install --prefix "$fixture" --package-lock=false --no-audit --no-fund --silent; node test/integration/verify-package.mjs; (cd "$fixture/npm_dist" && npm pack --dry-run)'

# === CODE QUALITY ===

# Format source code
format:
    gleam format src test

# Check formatting without changes
format-check:
    gleam format --check src test

# Type check without building
check:
    gleam check

# === DOCUMENTATION ===

# Build documentation
docs:
    gleam docs build

# === CHANGELOG ===

# Create a new changelog entry
change:
    changie new

# Preview unreleased changelog
changelog-preview:
    changie batch auto --dry-run

# Generate CHANGELOG.md
changelog:
    changie merge

# === MAINTENANCE ===

# Remove build artifacts
clean:
    rm -rf build

# === CI ===

# Run all CI checks (format, check, test, build, integration)
ci: format-check check test build-strict test-integration

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs

# =============================================================================
# MULTI-TARGET SUPPORT (Uncomment if targeting JavaScript)
# =============================================================================

# # Build for JavaScript target
# build-js:
#     gleam build --target javascript

# # Build all targets
# build-all: build build-js

# # Build JavaScript with warnings as errors
# build-strict-js:
#     gleam build --target javascript --warnings-as-errors

# # Build all targets strictly
# build-strict-all: build-strict build-strict-js

# # Test on Erlang target
# test-erlang:
#     gleam test

# # Test on JavaScript target
# test-js:
#     gleam test --target javascript

# # Test on all targets
# test-all: test-erlang test-js

# =============================================================================
# JAVASCRIPT INTEGRATION TESTS (Uncomment if needed)
# =============================================================================

# # Run integration tests with Node.js
# test-integration-node: build-js
#     node --test test/integration/test_runner.mjs

# # Run integration tests with Deno
# test-integration-deno: build-js
#     deno test --allow-read --allow-env test/integration/test_runner.mjs

# # Run integration tests with Bun
# test-integration-bun: build-js
#     bun test test/integration/test_runner.mjs

# =============================================================================
# COVERAGE (Uncomment if needed)
# =============================================================================

# # Run tests with coverage (requires setup - see README)
# coverage:
#     @echo "Coverage requires additional setup. See README.md"
