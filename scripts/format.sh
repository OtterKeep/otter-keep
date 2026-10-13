#!/usr/bin/env bash
#
# Formats Swift sources with the repository's `.swift-format` configuration.
#
# Usage:
#   scripts/format.sh                 # format every Swift file (Sources + Tests)
#   scripts/format.sh path/to/File.swift [more paths...]
#   scripts/format.sh --lint          # report violations without rewriting anything
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "--lint" ]]; then
    shift
    targets=("$@")
    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=(Sources Tests)
    fi
    swift format lint --recursive "${targets[@]}"
    exit 0
fi

if [[ $# -gt 0 ]]; then
    swift format --in-place "$@"
else
    swift format --in-place --recursive Sources Tests
fi

echo "✅ formatted with .swift-format"
