#!/usr/bin/env bash
#
# Runs the OtterKeep integration test suite.
#
# swift-testing expands `@Test`/`@Suite` through the TestingMacros compiler plugin. On a Command
# Line Tools-only toolchain SwiftPM's build sandbox rewrites the plugin-server path incorrectly and
# the first compile of the test target can fail if `libTestingMacros.dylib` is under `plugins/testing`.
# This wrapper passes the explicit plugin path when present, retries on transient macro load errors,
# and reports real test failures immediately.
#
# Usage:
#   scripts/test.sh                 # debug build, serial execution
#   scripts/test.sh -c release      # release build (used by CI)
#   scripts/test.sh --filter Module04Tests
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EXTRA_ARGS=()
CLT_PLUGIN_DIR="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
if [[ -d "$CLT_PLUGIN_DIR" ]]; then
    EXTRA_ARGS+=("-Xswiftc" "-plugin-path" "-Xswiftc" "$CLT_PLUGIN_DIR")
fi

ATTEMPTS="${OTTERKEEP_TEST_ATTEMPTS:-3}"
OUTPUT="$(mktemp -t otterkeep-tests)"
trap 'rm -f "$OUTPUT"' EXIT

for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if swift test --no-parallel --disable-sandbox "${EXTRA_ARGS[@]}" "$@" 2>&1 | tee "$OUTPUT"; then
        exit 0
    fi

    if grep -q "TestingMacros" "$OUTPUT" && ((attempt < ATTEMPTS)); then
        echo "⚠️  swift-testing macro plugin failed to load (toolchain packaging issue); retrying (${attempt}/${ATTEMPTS})..."
        continue
    fi

    exit 1
done

echo "❌ test suite did not complete after ${ATTEMPTS} attempts"
exit 1
