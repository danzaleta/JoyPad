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

echo "Assembling macOS Menu Bar App Bundle (${APP_DIR})..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"
cp "Info.plist" "${CONTENTS_DIR}/"

echo "Ad-hoc signing ${APP_DIR}..."
codesign --force -s - "${APP_DIR}"

echo "Done! Bundle available at: ${APP_DIR}"
