#!/bin/bash
set -e

# --- Configuration ---
APP_NAME="MyTerm"
BUNDLE_ID="com.nicelookingterminal.${APP_NAME}"
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_MACOS="13.0"

# --- Paths ---
PROJECT_ROOT="$(pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "🧹 Cleaning previous build artifacts..."
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "🎨 Generating App Icon from AppIcon.png if it exists..."
if [ -f "${PROJECT_ROOT}/AppIcon.png" ]; then
    mkdir -p "${PROJECT_ROOT}/AppIcon.iconset"
    sips -s format png -z 16 16     "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_16x16.png" > /dev/null 2>&1
    sips -s format png -z 32 32     "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_16x16@2x.png" > /dev/null 2>&1
    sips -s format png -z 32 32     "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_32x32.png" > /dev/null 2>&1
    sips -s format png -z 64 64     "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_32x32@2x.png" > /dev/null 2>&1
    sips -s format png -z 128 128   "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_128x128.png" > /dev/null 2>&1
    sips -s format png -z 256 256   "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_128x128@2x.png" > /dev/null 2>&1
    sips -s format png -z 256 256   "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_256x256.png" > /dev/null 2>&1
    sips -s format png -z 512 512   "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_256x256@2x.png" > /dev/null 2>&1
    sips -s format png -z 512 512   "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_512x512.png" > /dev/null 2>&1
    sips -s format png -z 1024 1024 "${PROJECT_ROOT}/AppIcon.png" --out "${PROJECT_ROOT}/AppIcon.iconset/icon_512x512@2x.png" > /dev/null 2>&1

    iconutil -c icns "${PROJECT_ROOT}/AppIcon.iconset" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "${PROJECT_ROOT}/AppIcon.iconset"
    echo "✨ App Icon created successfully!"
else
    echo "⚠️  Warning: AppIcon.png not found. App will compile with a generic system icon."
fi

echo "🏗️  Building ${APP_NAME} in Release mode..."
# Standard release build
swift build -c release

echo "📦 Packaging App Bundle..."
BINARY_SOURCE=".build/release/${APP_NAME}"

if [ ! -f "${BINARY_SOURCE}" ]; then
    echo "❌ Error: Binary not found at ${BINARY_SOURCE}"
    exit 1
fi

cp "${BINARY_SOURCE}" "${MACOS_DIR}/${APP_NAME}"

echo "📝 Generating Info.plist..."
cat > "${CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "${CONTENTS}/PkgInfo"

echo "🔏 Ad-hoc Signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Success! ${APP_NAME}.app is ready in ${DIST_DIR}"
echo ""
echo "🚀 To install: cp -R '${APP_BUNDLE}' /Applications/"
echo "📌 Then drag it from /Applications to your Dock."
