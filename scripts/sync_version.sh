#!/usr/bin/env bash
#
# Keeps every version literal in the repository derived from a single source: version.json.
#
# Usage:
#   scripts/sync_version.sh           # rewrite the derived literals (CoreEngine, packaging, appcast)
#   scripts/sync_version.sh --check   # verify everything is in sync; exits 1 on drift (CI gate)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 - "$ROOT" "$@" <<'PY'
import json
import os
import re
import sys

root = sys.argv[1]
check_only = "--check" in sys.argv[2:]

manifest_path = os.path.join(root, "version.json")
manifest = json.load(open(manifest_path))
version = manifest["version"]
build = manifest["build"]
subsystems = manifest["subsystems"]

core_engine = os.path.join(root, "Sources/OtterKeepCore/CoreEngine.swift")
package_script = os.path.join(root, "scripts/package_app.sh")
appcast = os.path.join(root, "Distribution/appcast.xml")

BEGIN = "    // MARK: - Version Manifest (generated from version.json by scripts/sync_version.sh)"
END = "    // <version-manifest:end>"

subsystem_props = [
    ("storageVersion", subsystems["OtterKeepStorage"]),
    ("databaseVersion", subsystems["OtterKeepDatabase"]),
    ("coreVersion", subsystems["OtterKeepCore"]),
    ("uiVersion", subsystems["OtterKeepUI"]),
    ("cliVersion", subsystems["OtterKeepCLI"]),
    ("finderSyncVersion", subsystems["OtterKeepFinderSyncExtension"]),
]

block_lines = [
    BEGIN,
    "    // <version-manifest:begin>",
    "    /// Semantic version identifier of the OtterKeep application (main product version).",
    '    public static let version = "%s"' % version,
    "",
    "    /// Internal build sequence number.",
    '    public static let buildNumber = "%s"' % build,
    "",
    "    /// Subsystem versions:",
]
block_lines += ['    public static let %s = "%s"' % (name, value) for name, value in subsystem_props]
block_lines += [END]
block = "\n".join(block_lines)

problems = []


def sync_core_engine():
    src = open(core_engine).read()
    pattern = re.compile(
        r"    // MARK: - Version Manifest.*?// <version-manifest:end>", re.S
    )
    if not pattern.search(src):
        problems.append("CoreEngine.swift: version manifest markers not found")
        return
    new = pattern.sub(lambda _: block, src, count=1)
    if new != src:
        if check_only:
            problems.append("CoreEngine.swift: version literals are out of sync with version.json")
        else:
            open(core_engine, "w").write(new)


def sync_package_script():
    src = open(package_script).read()
    pattern = re.compile(r'^APP_VERSION="\$\{3:-[^}]*\}"$', re.M)
    build_pattern = re.compile(r'^BUILD_VERSION="\$\{4:-[^}]*\}"$', re.M)
    if not pattern.search(src) or not build_pattern.search(src):
        problems.append("package_app.sh: APP_VERSION/BUILD_VERSION defaults not found")
        return
    new = pattern.sub('APP_VERSION="${3:-%s}"' % version, src, count=1)
    new = build_pattern.sub('BUILD_VERSION="${4:-%s}"' % build, new, count=1)
    if new != src:
        if check_only:
            problems.append("package_app.sh: version defaults are out of sync with version.json")
        else:
            open(package_script, "w").write(new)


SEMVER = r"[0-9][0-9A-Za-z.\-]*"


def sync_appcast():
    src = open(appcast).read()
    item_end = src.index("</item>")
    head, tail = src[:item_end], src[item_end:]
    original_head = head

    head = re.sub(
        r"<title>Version [^<]+</title>", "<title>Version %s</title>" % version, head, count=1
    )
    head = re.sub(r'sparkle:version="[^"]*"', 'sparkle:version="%s"' % build, head, count=1)
    head = re.sub(
        r'sparkle:shortVersionString="[^"]*"',
        'sparkle:shortVersionString="%s"' % version,
        head,
        count=1,
    )
    head = re.sub(
        r"releases/tag/v" + SEMVER, "releases/tag/v%s" % version, head, count=1
    )
    head = re.sub(
        r"releases/download/v" + SEMVER + r"/OtterKeep-" + SEMVER + r"\.zip",
        "releases/download/v%s/OtterKeep-%s.zip" % (version, version),
        head,
        count=1,
    )

    # Guard against over-matching: the item must keep its structure intact.
    for marker in ("</sparkle:releaseNotesLink>", "<description>", 'url="https'):
        if marker not in head:
            problems.append(
                "appcast.xml: rewrote the newest item but lost '%s'; aborting" % marker
            )
            return
    if "Version %s</title>" % version not in head or 'sparkle:version="%s"' % build not in head:
        problems.append("appcast.xml: newest item could not be updated/verified")
        return
    if head != original_head:
        if check_only:
            problems.append("appcast.xml: newest item is out of sync with version.json")
        else:
            open(appcast, "w").write(head + tail)


sync_core_engine()
sync_package_script()
sync_appcast()

if problems:
    print("❌ version drift detected:")
    for problem in problems:
        print("   -", problem)
    sys.exit(1)

if check_only:
    print("✅ version.json, CoreEngine.swift, package_app.sh and appcast.xml are in sync (%s / %s)" % (version, build))
else:
    print("✅ synchronized derived version literals to %s / %s" % (version, build))
PY
