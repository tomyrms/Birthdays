#!/usr/bin/env bash
# Construit une IPA non signée (Payload/Birthdays.app) pour signature locale
# avec Sideloadly. Aucun certificat ni profil de provisioning n'est requis :
# la compilation désactive entièrement la signature de code.
set -euo pipefail

export LC_ALL=C
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root_dir"

artifact_dir="$root_dir/artifacts/ios"
rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"

build_number="${BIRTHDAYS_BUILD:-$(date +%Y%m%d%H%M)}"
export BIRTHDAYS_BUILD="$build_number"

echo "== Projet Xcode (build $build_number)"
ruby scripts/generate_project.rb

archive_path="$artifact_dir/Birthdays.xcarchive"
derived_data="$artifact_dir/DerivedData"

echo "== Archive Release non signée"
xcodebuild archive \
  -project ios/Birthdays.xcodeproj \
  -scheme Birthdays \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data" \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM='' \
  2>&1 | tee "$artifact_dir/build.log"

app_path="$archive_path/Products/Applications/Birthdays.app"
if [[ ! -d "$app_path" ]]; then
  echo "Application absente de l'archive : $app_path" >&2
  exit 1
fi

staging_dir="$(mktemp -d "$artifact_dir/ipa.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/Birthdays.app"

staged_app="$staging_dir/Payload/Birthdays.app"
extension_path="$staged_app/PlugIns/BirthdaysWidgetExtension.appex"
if [[ ! -d "$extension_path" ]]; then
  echo "Extension widget absente : $extension_path" >&2
  exit 1
fi

# Ceinture et bretelles : retirer toute signature ou profil résiduels.
find "$staging_dir/Payload" -name '_CodeSignature' -type d -prune -exec rm -rf {} +
find "$staging_dir/Payload" -name 'embedded.mobileprovision' -type f -delete

for bundle in "$staged_app" "$extension_path"; do
  if codesign --display "$bundle" >/dev/null 2>&1; then
    echo "Bundle encore signé : $bundle" >&2
    exit 1
  fi
  if ! codesign --display "$bundle" 2>&1 | grep -q 'code object is not signed at all'; then
    echo "État de signature indéterminé : $bundle" >&2
    exit 1
  fi
done

echo "== Empaquetage"
cd "$staging_dir"
zip -qry "$artifact_dir/Birthdays.ipa" Payload
unzip -tq "$artifact_dir/Birthdays.ipa" >/dev/null

cd "$artifact_dir"
shasum -a 256 Birthdays.ipa > SHA256SUMS.txt

/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$staged_app/Info.plist" > version.txt
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$staged_app/Info.plist" > build.txt

cat > build-info.json <<EOF
{
  "application": "Birthdays",
  "version": "$(cat version.txt)",
  "build": "$(cat build.txt)",
  "bundleIdentifier": "ch.shulker.birthdays",
  "configuration": "Release",
  "signed": false,
  "commit": "${GITHUB_SHA:-local}",
  "run": "${GITHUB_RUN_ID:-local}",
  "ipaSHA256": "$(cut -d' ' -f1 SHA256SUMS.txt)",
  "installation": "Signer et installer avec Sideloadly"
}
EOF
rm -f version.txt build.txt

echo
echo "IPA non signée prête : $artifact_dir/Birthdays.ipa"
cat SHA256SUMS.txt
