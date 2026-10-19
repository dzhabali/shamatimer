#!/bin/bash
# Сборка и загрузка ShamaTimer в App Store Connect (TestFlight).
#   ASC_KEY_ID=XXXX ASC_ISSUER_ID=yyyy-... [DEVELOPMENT_TEAM=ABCDE12345] tools/upload.sh
# Ключ: ~/.appstoreconnect/AuthKey_$ASC_KEY_ID.p8
# Номер сборки (CURRENT_PROJECT_VERSION в project.yml) увеличивается на 1 перед каждой загрузкой.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?нужен ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?нужен ASC_ISSUER_ID}"
KEY_PATH="$HOME/.appstoreconnect/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$KEY_PATH" ] || { echo "нет ключа $KEY_PATH" >&2; exit 1; }

# 1. build number +1
cur=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/p' project.yml | head -1)
[ -n "$cur" ] || { echo "не нашёл CURRENT_PROJECT_VERSION в project.yml" >&2; exit 1; }
next=$((cur + 1))
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*)\"?[0-9]+\"?/\1\"${next}\"/" project.yml
echo "build ${cur} → ${next}"

# 2. проект
xcodegen generate

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")
TEAM=()
[ -n "${DEVELOPMENT_TEAM:-}" ] && TEAM=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")

ARCHIVE="build/ShamaTimer.xcarchive"
rm -rf "$ARCHIVE" build/export

# 3. archive
xcodebuild -project ShamaTimer.xcodeproj -scheme ShamaTimer -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  "${AUTH[@]}" ${TEAM[@]+"${TEAM[@]}"} archive

# 4. export + upload
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist tools/ExportOptions.plist -exportPath build/export \
  "${AUTH[@]}"

echo "загружено: v$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9.]+)"?.*/\1/p' project.yml | head -1) (${next})"
