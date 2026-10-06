#!/bin/zsh
# Build Muzify.app (universal: Apple Silicon + Intel) và đóng gói build/Muzify.zip
# Dùng: ./build.sh            → build
#       ./build.sh --install  → build rồi cài vào /Applications
set -e
cd "$(dirname "$0")"

python3 Scripts/l10n.py check >/dev/null || { python3 Scripts/l10n.py check; echo "✗ Thiếu bản dịch — sửa rồi build lại."; exit 1; }
Scripts/build_ios.sh --check >/dev/null || { echo "✗ Mã dùng chung với iOS bị lỗi — chạy Scripts/build_ios.sh --check để xem."; exit 1; }
echo "→ Build Apple Silicon (arm64)…"
swift build -c release --triple arm64-apple-macosx14.0
echo "→ Build Intel (x86_64)…"
swift build -c release --triple x86_64-apple-macosx14.0
[ -f Resources/AppIcon.icns ] || swift Scripts/make_icon.swift Resources/AppIcon.icns

APP=build/Muzify.app
rm -rf "$APP" build/Muzify.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  "$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/Muzify" \
  "$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/Muzify" \
  -output "$APP/Contents/MacOS/Muzify"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/vi.lproj Resources/en.lproj "$APP/Contents/Resources/"
strip -x "$APP/Contents/MacOS/Muzify"
xattr -cr "$APP"
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" build/Muzify.zip
echo "✓ $APP ($(du -sh "$APP" | cut -f1)) · $(lipo -archs "$APP/Contents/MacOS/Muzify")"
echo "✓ build/Muzify.zip ($(du -h build/Muzify.zip | cut -f1))"

if [ "$1" = "--install" ]; then
  pkill -x Muzify 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Muzify.app
  cp -R "$APP" /Applications/
  echo "✓ Đã cài vào /Applications"
fi
