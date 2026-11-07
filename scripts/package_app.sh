#!/usr/bin/env bash
set -e

# ==============================================================================
# 📦 OtterKeep Application & FinderSync Extension Packager
# Builds, bundles, codesigns, and registers OtterKeep.app with macOS LaunchServices.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-release}"
TARGET_DIR="${2:-$HOME/Applications}"
APP_VERSION="${3:-2.0.0}"
BUILD_VERSION="${4:-2000}"


echo "======================================================="
echo "📦 Packaging OtterKeep.app ($CONFIGURATION mode)"
echo "   Target directory: $TARGET_DIR"
echo "======================================================="

cd "$PROJECT_ROOT"

echo "🔨 1. Compiling OtterKeepApp, OtterKeepFinderSyncExtension, and otterkeep CLI..."
swift build -c "$CONFIGURATION" --product OtterKeepApp
swift build -c "$CONFIGURATION" --product OtterKeepFinderSyncExtension
swift build -c "$CONFIGURATION" --product otterkeep

APP_BINARY=""
EXT_BINARY=""
CLI_BINARY=""

# Try common output directories
for candidate_dir in "$PROJECT_ROOT/.build/$CONFIGURATION" "$PROJECT_ROOT/.build/out/Products/$CONFIGURATION" "$PROJECT_ROOT/.build/arm64-apple-macosx/$CONFIGURATION" "$PROJECT_ROOT/.build/x86_64-apple-macosx/$CONFIGURATION"; do
    if [ -f "$candidate_dir/OtterKeepApp" ] && [ -z "$APP_BINARY" ]; then
        APP_BINARY="$candidate_dir/OtterKeepApp"
    fi
    if [ -f "$candidate_dir/OtterKeepFinderSyncExtension" ] && [ -z "$EXT_BINARY" ]; then
        EXT_BINARY="$candidate_dir/OtterKeepFinderSyncExtension"
    fi
    if [ -f "$candidate_dir/otterkeep" ] && [ -z "$CLI_BINARY" ]; then
        CLI_BINARY="$candidate_dir/otterkeep"
    fi
done

# Fallback search if not located yet
if [ -z "$APP_BINARY" ] || [ ! -f "$APP_BINARY" ]; then
    APP_BINARY=$(find "$PROJECT_ROOT/.build" -name "OtterKeepApp" -type f 2>/dev/null | grep -i "$CONFIGURATION" | head -n 1)
fi
if [ -z "$EXT_BINARY" ] || [ ! -f "$EXT_BINARY" ]; then
    EXT_BINARY=$(find "$PROJECT_ROOT/.build" -name "OtterKeepFinderSyncExtension" -type f 2>/dev/null | grep -i "$CONFIGURATION" | head -n 1)
fi
if [ -z "$CLI_BINARY" ] || [ ! -f "$CLI_BINARY" ]; then
    CLI_BINARY=$(find "$PROJECT_ROOT/.build" -name "otterkeep" -type f 2>/dev/null | grep -i "$CONFIGURATION" | head -n 1)
fi

echo "   OtterKeepApp: $APP_BINARY"
echo "   OtterKeepFinderSyncExtension: $EXT_BINARY"
echo "   otterkeep CLI: $CLI_BINARY"

if [ -z "$APP_BINARY" ] || [ ! -f "$APP_BINARY" ] || [ -z "$EXT_BINARY" ] || [ ! -f "$EXT_BINARY" ] || [ -z "$CLI_BINARY" ] || [ ! -f "$CLI_BINARY" ]; then
    echo "❌ Error: Required binaries not found."
    exit 1
fi

APP_BUNDLE="$TARGET_DIR/OtterKeep.app"
APPEX_BUNDLE="$APP_BUNDLE/Contents/PlugIns/OtterKeepFinderSync.appex"

echo "📂 2. Assembling bundle structure at $APP_BUNDLE..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APPEX_BUNDLE/Contents/MacOS"
mkdir -p "$APPEX_BUNDLE/Contents/Resources"

echo "🎨 3. Installing AppIcon.icns and UI Resource Bundles..."
# Generate AppIcon.icns if not present
if [ ! -f "$PROJECT_ROOT/Sources/OtterKeepUI/Resources/AppIcon.icns" ]; then
    python3 -c '
import os, subprocess, shutil
src = "Sources/OtterKeepUI/Resources/OtterKeepLogo.jpg"
iconset = "Sources/OtterKeepUI/Resources/AppIcon.iconset"
if os.path.exists(iconset): shutil.rmtree(iconset)
os.makedirs(iconset, exist_ok=True)
sizes = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for name, sz in sizes:
    subprocess.run(["sips", "-s", "format", "png", "-z", str(sz), str(sz), src, "--out", os.path.join(iconset, name)], check=True, stdout=subprocess.DEVNULL)
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", "Sources/OtterKeepUI/Resources/AppIcon.icns"], check=True)
shutil.rmtree(iconset)
'
fi

cp "$PROJECT_ROOT/Sources/OtterKeepUI/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy OtterKeep_OtterKeepUI.bundle if built by SPM
UI_BUNDLE=$(find "$PROJECT_ROOT/.build" -name "OtterKeep_OtterKeepUI.bundle" -type d | head -n 1)
if [ -n "$UI_BUNDLE" ]; then
    echo "   📦 Copying OtterKeep_OtterKeepUI.bundle to Contents/Resources..."
    cp -R "$UI_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

echo "📄 4. Writing Info.plist manifests..."
cat << EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.otterkeep.OtterKeepApp</string>
    <key>CFBundleName</key>
    <string>OtterKeep</string>
    <key>CFBundleDisplayName</key>
    <string>OtterKeep</string>
    <key>CFBundleExecutable</key>
    <string>OtterKeepApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>OtterKeep needs access to your Photos library to create incremental backups of your photos, videos, and albums.</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>OtterKeep needs access to your Photos library to restore photos and albums.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.otterkeep.restore</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>otterkeep</string>
            </array>
        </dict>
    </array>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/OtterKeep/otter-keep/main/Distribution/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>f1K6iA545H/Q4qJ5+f/1sL7bL6lC55JmQo6W+9yE7yQ=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>OtterKeep: Előző verziók böngészése...</string>
            </dict>
            <key>NSMessage</key>
            <string>openVersionHistoryService</string>
            <key>NSPortName</key>
            <string>OtterKeepApp</string>
            <key>NSRequiredContext</key>
            <dict/>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
            <key>NSSendTypes</key>
            <array>
                <string>NSFilenamesPboardType</string>
                <string>public.file-url</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

cat << EOF > "$APPEX_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.otterkeep.OtterKeepApp.FinderSync</string>
    <key>CFBundleName</key>
    <string>OtterKeepFinderSync</string>
    <key>CFBundleDisplayName</key>
    <string>OtterKeep Finder Integration</string>
    <key>CFBundleExecutable</key>
    <string>OtterKeepFinderSyncExtension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict/>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>OtterKeepFinderSync</string>
    </dict>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "📥 5. Installing binaries & embedded frameworks..."
cp "$APP_BINARY" "$APP_BUNDLE/Contents/MacOS/OtterKeepApp"
cp "$EXT_BINARY" "$APPEX_BUNDLE/Contents/MacOS/OtterKeepFinderSyncExtension"
cp "$CLI_BINARY" "$APP_BUNDLE/Contents/MacOS/otterkeep"
chmod +x "$APP_BUNDLE/Contents/MacOS/OtterKeepApp"
chmod +x "$APPEX_BUNDLE/Contents/MacOS/OtterKeepFinderSyncExtension"
chmod +x "$APP_BUNDLE/Contents/MacOS/otterkeep"

mkdir -p "$APP_BUNDLE/Contents/Frameworks"
SPARKLE_FW=$(find "$PROJECT_ROOT/.build" -name "Sparkle.framework" -type d 2>/dev/null | head -n 1)
if [ -n "$SPARKLE_FW" ]; then
    echo "   📦 Copying Sparkle.framework to Contents/Frameworks..."
    cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
fi

# Ensure LC_RPATH contains @executable_path/../Frameworks for dynamic frameworks (e.g. Sparkle)
if ! otool -l "$APP_BUNDLE/Contents/MacOS/OtterKeepApp" | grep -q "@executable_path/../Frameworks"; then
    echo "   🔗 Adding @executable_path/../Frameworks rpath to OtterKeepApp..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/OtterKeepApp"
fi

echo "🔐 6. Hierarchical code signing..."
if [ -z "${APPLE_DEVELOPER_IDENTITY:-}" ]; then
    DETECTED_ID=$(security find-identity -p codesigning -v 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}' || true)
    if [ -n "$DETECTED_ID" ]; then
        SIGN_IDENTITY="$DETECTED_ID"
        echo "   Using detected codesigning identity: $SIGN_IDENTITY"
    else
        SIGN_IDENTITY="-"
        echo "   Using ad-hoc codesigning (-)"
    fi
else
    SIGN_IDENTITY="$APPLE_DEVELOPER_IDENTITY"
    echo "   Using specified codesigning identity: $SIGN_IDENTITY"
fi

if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
    if [ -f "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/Current/Autoupdate" ]; then
        codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/Current/Autoupdate" 2>/dev/null || true
    fi
    codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi

TEMP_ENTITLEMENTS="$(mktemp /tmp/otterkeep_ent.XXXXXX.plist)"
cat << 'EOF' > "$TEMP_ENTITLEMENTS"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
    <array>
        <string>/.otterkeep/</string>
    </array>
</dict>
</plist>
EOF

codesign --force --sign "$SIGN_IDENTITY" --entitlements "$TEMP_ENTITLEMENTS" "$APPEX_BUNDLE"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/otterkeep"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/OtterKeepApp"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
rm -f "$TEMP_ENTITLEMENTS"

# Strip quarantine attributes so locally packaged application launches without unidentified developer warnings
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo "🐚 7. Generating shell completions..."
mkdir -p "$PROJECT_ROOT/Distribution/completions"
"$CLI_BINARY" --generate-completion-script zsh > "$PROJECT_ROOT/Distribution/completions/_otterkeep" 2>/dev/null || true
"$CLI_BINARY" --generate-completion-script bash > "$PROJECT_ROOT/Distribution/completions/otterkeep.bash" 2>/dev/null || true
"$CLI_BINARY" --generate-completion-script fish > "$PROJECT_ROOT/Distribution/completions/otterkeep.fish" 2>/dev/null || true

if [ -z "$SKIP_REGISTER" ]; then
    echo "📡 8. Registering with LaunchServices, Services, and PluginKit..."
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ -f "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$APP_BUNDLE"
    fi

    touch "$APP_BUNDLE"

    defaults write pbs NSServicesStatus -dict-add "com.otterkeep.OtterKeepApp - OtterKeep: Előző verziók böngészése... - openVersionHistoryService" '{
        "enabled_context_menu" = 1;
        "enabled_services_menu" = 1;
        "presentation_modes" = {
            ContextMenu = 1;
            ServicesMenu = 1;
        };
    }' 2>/dev/null || true
    /System/Library/CoreServices/pbs -update 2>/dev/null || true

    pluginkit -a "$APPEX_BUNDLE" || true
    pluginkit -e use -i com.otterkeep.OtterKeepApp.FinderSync || true

    echo "✅ Verifying PluginKit status:"
    pluginkit -m -p com.apple.FinderSync | grep -i "otterkeep" || true

    echo "🔄 8. Restarting Finder to attach extension..."
    killall Finder || true
fi

echo "🎉 OtterKeep.app successfully packaged at: $APP_BUNDLE"
