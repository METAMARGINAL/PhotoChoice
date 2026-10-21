#!/bin/bash
# Собирает build/PhotoChoice.dmg для GitHub Releases: приложение и ярлык «Программы» для перетаскивания.
#
#   ./scripts/make-dmg.sh
#       подпись «только для этого Mac»: на другом Mac первый запуск — через «Всё равно открыть»
#
#   DEVELOPER_ID="Developer ID Application: Имя (TEAMID)" NOTARY_PROFILE=photochoice ./scripts/make-dmg.sh
#       подпись Developer ID и нотаризация Apple: открывается без предупреждений.
#       Профиль один раз: xcrun notarytool store-credentials photochoice --apple-id … --team-id …
set -euo pipefail
cd "$(dirname "$0")/.."

APP=PhotoChoice
OUT=build/release
DMG=build/$APP.dmg
MODELS=PhotoChoice/Models

# В релизе нет текстовой части MobileCLIP — подсказки должны лежать готовыми
if [ ! -f "$MODELS/prompts.json" ]; then
    echo "Нет $MODELS/prompts.json — без него «Размыто» работает без проверки моделью." >&2
    exit 1
fi
# Без git lfs pull вместо весов лежат текстовые ссылки на них
for weights in "$MODELS"/*.mlpackage/Data/com.apple.CoreML/weights/weight.bin; do
    if head -c 100 "$weights" | grep -q "git-lfs"; then
        echo "Модель не скачана из Git LFS: $weights — выполните git lfs pull." >&2
        exit 1
    fi
done

rm -rf "$OUT" "$DMG"
xcodebuild -project PhotoChoice.xcodeproj -scheme PhotoChoice -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$OUT/derived" -quiet build
BUILT="$OUT/derived/Build/Products/Release/$APP.app"

if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements PhotoChoice/PhotoChoice.entitlements --sign "$DEVELOPER_ID" "$BUILT"
fi
codesign --verify --strict "$BUILT"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$BUILT" "$STAGE/$APP.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:?Укажите NOTARY_PROFILE}" --wait
    xcrun stapler staple "$DMG"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUILT/Contents/Info.plist")
# Текст релиза — раздел этой версии из CHANGELOG.md
awk -v head="## $VERSION " 'index($0, head) == 1 { on = 1; next } /^## / && on { exit } on' CHANGELOG.md > build/release-notes.md
echo "Готово: $DMG ($(du -h "$DMG" | cut -f1)), версия $VERSION"
echo "Выложить: gh release create v$VERSION $DMG --title \"PhotoChoice $VERSION\" --notes-file build/release-notes.md"
