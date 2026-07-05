#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Shredder.app"
ICON_SOURCE="$ROOT/Assets/AppIcon.png"

cd "$ROOT"
mkdir -p "$ROOT/build/module-cache" "$ROOT/build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/build/module-cache"
export XDG_CACHE_HOME="$ROOT/build/swiftpm-cache"
swift build --disable-sandbox -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/icon.iconset"
cp ".build/release/Shredder" "$APP/Contents/MacOS/Shredder"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ROOT/build/icon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_SOURCE" --out "$ROOT/build/icon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$ROOT/scripts/make_icns.py" "$ROOT/build/icon.iconset" "$APP/Contents/Resources/AppIcon.icns"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "$APP"
