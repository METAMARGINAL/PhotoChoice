#!/bin/bash
# Собирает Release и ставит поверх /Applications/PhotoChoice.app.
# Звёзды, цвета, кэш анализа и настройки лежат в ~/Library/Containers/VS.PhotoChoice — они остаются.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=PhotoChoice
OUT=build/install
TARGET=/Applications/$APP.app

xcodebuild -project PhotoChoice.xcodeproj -scheme PhotoChoice -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$OUT" -quiet build
BUILT="$OUT/Build/Products/Release/$APP.app"

# Открытое приложение сначала закрываем — оно успеет сохранить оценки и кэш
osascript -e "quit app \"$APP\"" 2>/dev/null || true
while pgrep -x "$APP" >/dev/null; do sleep 0.5; done

rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$TARGET/Contents/Info.plist")
echo "Установлен $APP $VERSION"
open "$TARGET"
