#!/bin/zsh
set -e

APP_NAME="JoyPadServer"
BUILD_DIR=".build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building JoyPad (Release)..."
swift build -c release

echo "Assembling macOS Companion App Bundle (${APP_DIR})..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"
cp "Info.plist" "${CONTENTS_DIR}/"

# Sign with Apple Development certificate if available so macOS TCC Accessibility persists across builds
CERT_NAME="Apple Development: dan_zaleta16@icloud.com (H7P9P7FGWC)"
if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    echo "Signing ${APP_DIR} with ${CERT_NAME}..."
    codesign --force -s "${CERT_NAME}" "${APP_DIR}"
else
    echo "Ad-hoc signing ${APP_DIR}..."
    codesign --force -s - "${APP_DIR}"
fi

echo "Installing to /Applications/${APP_NAME}.app..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"

echo "Done! Installed at /Applications/${APP_NAME}.app"
