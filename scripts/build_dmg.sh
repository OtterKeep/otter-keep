#!/usr/bin/env bash
set -e

# ==============================================================================
# 💽 OtterKeep DMG Creator
# Builds OtterKeep.app and packages it into a distributable, compressed .dmg file.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-2.0.0}"
CONFIGURATION="${2:-release}"
BUILD_NUMBER="${3:-2000}"

OUTPUT_DIR="$PROJECT_ROOT/.build/dist/"
DMG_NAME="OtterKeep-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "======================================================="
echo "💽 Creating OtterKeep DMG installer (v$VERSION / build $BUILD_NUMBER - $CONFIGURATION)"
echo "   Output: $DMG_PATH"
echo "======================================================="

# 1. Staging directory setup inside .build
STAGING_DIR="$PROJECT_ROOT/.build/dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

APP_TARGET_DIR="$STAGING_DIR/app"
mkdir -p "$APP_TARGET_DIR"
mkdir -p "$OUTPUT_DIR"

# 2. Package the .app bundle into staging
echo "📦 1. Building and packaging OtterKeep.app..."
SKIP_REGISTER=1 "$SCRIPT_DIR/package_app.sh" "$CONFIGURATION" "$APP_TARGET_DIR" "$VERSION" "$BUILD_NUMBER"

SOURCE_APP="$APP_TARGET_DIR/OtterKeep.app"
if [ ! -d "$SOURCE_APP" ]; then
    if [ -d "$HOME/Applications/OtterKeep.app" ]; then
        echo "   ℹ️ Using existing build from $HOME/Applications/OtterKeep.app"
        SOURCE_APP="$HOME/Applications/OtterKeep.app"
    else
        echo "❌ Error: OtterKeep.app was not found."
        exit 1
    fi
fi

# 3. Prepare DMG root contents
echo "📂 2. Preparing DMG image contents..."
DMG_ROOT="$STAGING_DIR/dmg_root"
mkdir -p "$DMG_ROOT"

cp -R "$SOURCE_APP" "$DMG_ROOT/OtterKeep.app"
ln -s /Applications "$DMG_ROOT/Applications"

# Optional: Copy README or documentation if desired
if [ -f "$PROJECT_ROOT/LICENSE" ]; then
    cp "$PROJECT_ROOT/LICENSE" "$DMG_ROOT/LICENSE.txt"
fi

# 4. Generate the DMG using macOS native hdiutil
echo "🚀 3. Creating compressed UDZO disk image with hdiutil..."
rm -f "$DMG_PATH"

hdiutil create \
    -volname "OtterKeep" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# 5. Generate SHA256 checksum for DMG
echo "🔒 4. Generating SHA256 checksum for DMG..."
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

# 6. Generate ZIP archive (for Homebrew Cask & Sparkle updates)
echo "📦 5. Creating ZIP archive for Homebrew Cask & Sparkle..."
ZIP_NAME="OtterKeep-${VERSION}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
(cd "$APP_TARGET_DIR" && zip -r -y -q "$ZIP_PATH" "OtterKeep.app")
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

# 7. Maintain Sparkle Distribution/appcast.xml
# 7. Maintain Sparkle Distribution/appcast.xml (Cumulative, non-destructive)
echo "📡 6. Updating Sparkle Appcast feed at Distribution/appcast.xml..."
mkdir -p "$PROJECT_ROOT/Distribution"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat -c%s "$ZIP_PATH" 2>/dev/null || echo "0")
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

python3 -c '
import sys, re, os

appcast_path = sys.argv[1]
version = sys.argv[2]
build_number = sys.argv[3]
zip_name = sys.argv[4]
zip_size = sys.argv[5]
pub_date = sys.argv[6]

new_item = f"""        <item>
            <title>Version {version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:releaseNotesLink>https://github.com/OtterKeep/otter-keep/releases/tag/v{version}</sparkle:releaseNotesLink>
            <description><![CDATA[OtterKeep {version} release.]]></description>
            <enclosure
                url="https://github.com/OtterKeep/otter-keep/releases/download/v{version}/{zip_name}"
                sparkle:version="{build_number}"
                sparkle:shortVersionString="{version}"
                length="{zip_size}"
                type="application/octet-stream" />
        </item>"""

if not os.path.exists(appcast_path):
    skeleton = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/sparrow/rss" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>OtterKeep Changelog</title>
        <link>https://github.com/OtterKeep/otter-keep</link>
        <description>Most recent updates and releases for OtterKeep on macOS.</description>
        <language>en</language>
{new_item}
    </channel>
</rss>
"""
    with open(appcast_path, "w", encoding="utf-8") as f:
        f.write(skeleton)
    print("   ✅ Generated initial Distribution/appcast.xml")
else:
    with open(appcast_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Check if this version is already present in appcast.xml
    pattern = rf"<item>[\s\S]*?sparkle:shortVersionString=\"{re.escape(version)}\"[\s\S]*?</item>"
    if re.search(pattern, content):
        # Update existing item in place (preserving older versions)
        updated = re.sub(pattern, new_item.strip(), content)
        with open(appcast_path, "w", encoding="utf-8") as f:
            f.write(updated)
        print(f"   🔄 Updated existing v{version} item in Distribution/appcast.xml")
    else:
        # Prepend new item before the first existing <item> to maintain reverse-chronological order
        if "<item>" in content:
            updated = content.replace("<item>", new_item.strip() + "\n        <item>", 1)
        else:
            updated = content.replace("</channel>", new_item + "\n    </channel>")
        with open(appcast_path, "w", encoding="utf-8") as f:
            f.write(updated)
        print(f"   ✨ Prepended v{version} item to Distribution/appcast.xml (previous versions preserved)")
' "$PROJECT_ROOT/Distribution/appcast.xml" "$VERSION" "$BUILD_NUMBER" "$ZIP_NAME" "$ZIP_SIZE" "$PUB_DATE"

echo "======================================================="
echo "🎉 Distribution artifacts successfully created!"
echo "   DMG:      $DMG_PATH"
echo "   Size:     $(du -h "$DMG_PATH" | cut -f1)"
echo "   SHA256:   $(cat "$DMG_PATH.sha256")"
echo "   ---"
echo "   ZIP:      $ZIP_PATH"
echo "   Size:     $(du -h "$ZIP_PATH" | cut -f1)"
echo "   SHA256:   $(cat "$ZIP_PATH.sha256")"
echo "   ---"
echo "   Appcast:  $PROJECT_ROOT/Distribution/appcast.xml"
echo "======================================================="
