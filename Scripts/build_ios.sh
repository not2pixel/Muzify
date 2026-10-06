#!/bin/zsh
# Build Muzify cho iPhone / iPad.
# Dùng: Scripts/build_ios.sh           → build/Muzify.ipa (chưa ký — cài bằng PlayCover / AltStore / Sideloadly)
#       Scripts/build_ios.sh --sim     → build/Muzify-sim.app (chạy trên Simulator)
#       Scripts/build_ios.sh --check   → chỉ kiểm tra kiểu trên Mac (không cần Xcode)
# Cần Xcode (có iOS SDK) cho 2 chế độ đầu.
set -e
cd "$(dirname "$0")/.."

SOURCES=(Sources/Muzify/Core/*.swift Sources/Muzify/UI/Theme.swift Sources/Muzify/UI/AppState.swift
         Sources/Muzify/UI/Tracks.swift Sources/MuzifyMobile/*.swift)
MODE=${1:-ipa}

python3 Scripts/l10n.py check >/dev/null || { python3 Scripts/l10n.py check; echo "✗ Thiếu bản dịch — sửa rồi build lại."; exit 1; }

if [ "$MODE" = "--check" ]; then
  swiftc -typecheck -parse-as-library -target arm64-apple-macos14.0 "${SOURCES[@]}"
  echo "✓ Mã iOS hợp lệ (kiểm tra kiểu trên macOS)"
  exit 0
fi

if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "✗ Chưa có iOS SDK. Cài Xcode từ App Store rồi chạy:"
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "    sudo xcodebuild -license accept"
  echo "    xcodebuild -downloadPlatform iOS"
  exit 1
fi

if [ "$MODE" = "--sim" ]; then
  SDK=iphonesimulator; TARGET=arm64-apple-ios17.0-simulator; APP=build/Muzify-sim.app
else
  SDK=iphoneos; TARGET=arm64-apple-ios17.0; APP=build/ios/Payload/Muzify.app
fi

echo "→ Biên dịch ($SDK)…"
rm -rf "$APP"; mkdir -p "$APP"
xcrun --sdk $SDK swiftc -O -parse-as-library -target $TARGET -sdk "$(xcrun --sdk $SDK --show-sdk-path)" \
  -module-name Muzify -o "$APP/Muzify" "${SOURCES[@]}"

cp Resources/iOS/Info.plist "$APP/"
cp -R Resources/vi.lproj Resources/en.lproj "$APP/"
cp Resources/iOS/Icons/*.png "$APP/"

if [ "$MODE" = "--sim" ]; then
  codesign --force --sign - "$APP"
  echo "✓ $APP"
  exit 0
fi

# .ipa chưa ký (PlayCover / AltStore / Sideloadly sẽ tự ký khi cài)
codesign --force --sign - "$APP" 2>/dev/null || true
rm -f build/Muzify.ipa
(cd build/ios && zip -qry ../Muzify.ipa Payload)
echo "✓ build/Muzify.ipa ($(du -h build/Muzify.ipa | cut -f1))"
