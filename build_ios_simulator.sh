#!/bin/zsh
set -e

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR

APP_NAME="JoyPadClient"
BUILD_DIR=".build/out/Products/Debug-iphonesimulator"
BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}.app"

echo "📱 Compilando JoyPadClientApp para iOS Simulator (Swift 6.4)..."
swift build --triple arm64-apple-ios17.0-simulator --target JoyPadClientApp

echo "📦 Creando bundle ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}"

cp "${BUILD_DIR}/JoyPadClientApp" "${BUNDLE_DIR}/${APP_NAME}"

cat <<EOF > "${BUNDLE_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.danzaleta.joypad.client</string>
    <key>CFBundleName</key>
    <string>JoyPad</string>
    <key>CFBundleDisplayName</key>
    <string>JoyPad</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UILaunchScreen</key>
    <dict/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>JoyPad necesita conectarse a tu Mac para enviar controles en tiempo real.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_joypad._udp</string>
        <string>_joypad._tcp</string>
    </array>
</dict>
</plist>
EOF

echo "🔏 Firmando ad-hoc..."
codesign --force -s - "${BUNDLE_DIR}"

echo "✅ JoyPadClient.app listo en: ${BUNDLE_DIR}"

# Si se pasa el argumento --run, arrancar simulador e instalar
if [[ "$1" == "--run" ]]; then
    DEVICE_ID=$(xcrun simctl list devices available | grep -E "iPhone 17|iPhone 18|iPhone Air" | head -n 1 | grep -oE "\([0-9A-F-]+\)" | tr -d "()")
    if [[ -z "$DEVICE_ID" ]]; then
        DEVICE_ID="booted"
    fi
    echo "🚀 Abriendo Simulador de iOS (${DEVICE_ID})..."
    open -a Simulator
    xcrun simctl boot "${DEVICE_ID}" 2>/dev/null || true
    echo "📲 Instalando JoyPadClient en el simulador..."
    xcrun simctl install booted "${BUNDLE_DIR}"
    echo "▶️ Lanzando JoyPad..."
    xcrun simctl launch booted com.danzaleta.joypad.client
fi
