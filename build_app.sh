#!/bin/bash
set -euo pipefail

APP_NAME="NiceLookingTerminal"
BINARY_NAME="MyTerm"
BUNDLE_ID="com.nicelookingterminal.app"
VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
MIN_MACOS="13.0"
BUILD_MODE="${BUILD_MODE:-local}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_PROFILE:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="${SCRIPT_DIR}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
INFO_PLIST="${CONTENTS}/Info.plist"
TEMP_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nicelookingterminal.XXXXXX")"
ICONSET_DIR="${TEMP_BUILD_DIR}/AppIcon.iconset"
DMG_ROOT="${TEMP_BUILD_DIR}/dmg-root"
NOTARY_ZIP="${TEMP_BUILD_DIR}/${APP_NAME}.zip"
UNIVERSAL_BINARY="${TEMP_BUILD_DIR}/${BINARY_NAME}"
SWIFT_BUILD_ARGS=(--package-path "${PROJECT_ROOT}" -c release)

cleanup() {
    rm -rf -- "${TEMP_BUILD_DIR}"
}
trap cleanup EXIT

case "${BUILD_MODE}" in
    local)
        SIGNING_IDENTITY="-"
        DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-local.dmg"
        ;;
    distribution)
        if [[ -z "${SIGNING_IDENTITY}" || -z "${NOTARY_KEYCHAIN_PROFILE}" ]]; then
            echo "Distribution builds require CODE_SIGN_IDENTITY and NOTARY_PROFILE." >&2
            exit 2
        fi
        if ! security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
            echo "The requested Developer ID signing identity is not installed: ${SIGNING_IDENTITY}" >&2
            exit 3
        fi
        DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
        ;;
    *)
        echo "BUILD_MODE must be 'local' or 'distribution'." >&2
        exit 2
        ;;
esac

if [[ "${DIST_DIR}" != "${PROJECT_ROOT}/dist" || -z "${PROJECT_ROOT}" ]]; then
    echo "Refusing to clean an unexpected output directory: ${DIST_DIR}" >&2
    exit 4
fi

rm -rf -- "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${ICONSET_DIR}" "${DMG_ROOT}"

if [[ -f "${PROJECT_ROOT}/AppIcon.png" ]]; then
    sips -s format png -z 16 16     "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
    sips -s format png -z 32 32     "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
    sips -s format png -z 32 32     "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
    sips -s format png -z 64 64     "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
    sips -s format png -z 128 128   "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
    sips -s format png -z 256 256   "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
    sips -s format png -z 256 256   "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
    sips -s format png -z 512 512   "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
    sips -s format png -z 512 512   "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
    sips -s format png -z 1024 1024 "${PROJECT_ROOT}/AppIcon.png" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
fi

if [[ "${BUILD_MODE}" == "distribution" ]]; then
    ARM_TRIPLE="arm64-apple-macosx${MIN_MACOS}"
    INTEL_TRIPLE="x86_64-apple-macosx${MIN_MACOS}"
    swift build "${SWIFT_BUILD_ARGS[@]}" --triple "${ARM_TRIPLE}"
    swift build "${SWIFT_BUILD_ARGS[@]}" --triple "${INTEL_TRIPLE}"
    ARM_BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --triple "${ARM_TRIPLE}" --show-bin-path)"
    INTEL_BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --triple "${INTEL_TRIPLE}" --show-bin-path)"
    lipo -create "${ARM_BIN_DIR}/${BINARY_NAME}" "${INTEL_BIN_DIR}/${BINARY_NAME}" -output "${UNIVERSAL_BINARY}"
    UNIVERSAL_ARCHITECTURES="$(lipo -archs "${UNIVERSAL_BINARY}")"
    if [[ " ${UNIVERSAL_ARCHITECTURES} " != *" arm64 "* || " ${UNIVERSAL_ARCHITECTURES} " != *" x86_64 "* ]]; then
        echo "Universal binary is missing a required architecture: ${UNIVERSAL_ARCHITECTURES}" >&2
        exit 5
    fi
    BINARY_SOURCE="${UNIVERSAL_BINARY}"
else
    swift build "${SWIFT_BUILD_ARGS[@]}"
    BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
    BINARY_SOURCE="${BIN_DIR}/${BINARY_NAME}"
fi
if [[ ! -x "${BINARY_SOURCE}" ]]; then
    echo "Release binary not found: ${BINARY_SOURCE}" >&2
    exit 5
fi
cp "${BINARY_SOURCE}" "${MACOS_DIR}/${APP_NAME}"

plutil -create xml1 "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${BUNDLE_ID}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string ${MIN_MACOS}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSDesktopFolderUsageDescription string NiceLookingTerminal runs your commands and agents in folders you choose." "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSDocumentsFolderUsageDescription string NiceLookingTerminal runs your commands and agents in folders you choose." "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSDownloadsFolderUsageDescription string NiceLookingTerminal runs your commands and agents in folders you choose." "${INFO_PLIST}"
if [[ -f "${RESOURCES_DIR}/AppIcon.icns" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${INFO_PLIST}"
fi
printf 'APPL????' > "${CONTENTS}/PkgInfo"

if [[ "${BUILD_MODE}" == "distribution" ]]; then
    codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
    codesign --force --sign - "${APP_BUNDLE}"
fi
codesign --verify --strict --verbose=2 "${APP_BUNDLE}"

if [[ "${BUILD_MODE}" == "distribution" ]]; then
    ditto -c -k --keepParent "${APP_BUNDLE}" "${NOTARY_ZIP}"
    xcrun notarytool submit "${NOTARY_ZIP}" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
    xcrun stapler staple "${APP_BUNDLE}"
    xcrun stapler validate "${APP_BUNDLE}"
    spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"
fi

ditto "${APP_BUNDLE}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DMG_PATH}" >/dev/null

if [[ "${BUILD_MODE}" == "distribution" ]]; then
    codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
    spctl --assess --type open --context context:primary-signature --verbose=4 "${DMG_PATH}"
fi

shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"
echo "Built ${APP_BUNDLE}"
echo "Built ${DMG_PATH}"
if [[ "${BUILD_MODE}" == "local" ]]; then
    echo "Local build is ad-hoc signed and intentionally not distributable. Use BUILD_MODE=distribution with Apple signing credentials for release."
fi
