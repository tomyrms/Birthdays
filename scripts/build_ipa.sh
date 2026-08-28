#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
archive_path="$project_root/build/Birthdays.xcarchive"
export_path="$project_root/build/IPA"

# Incrémenter le build à chaque IPA : sans numéro distinct, iOS réinstalle
# l'app mais conserve le widget en cache, qui garde l'affichage précédent.
build_number_file="$project_root/config/build-number"
current_build="$(cat "$build_number_file" 2>/dev/null || print 20)"
next_build=$(( current_build + 1 ))
print "$next_build" > "$build_number_file"
export BIRTHDAYS_BUILD="$next_build"
print "Build $next_build\n"

ruby "$project_root/scripts/generate_project.rb"
mkdir -p "$project_root/build"

xcodebuild \
  -project "$project_root/ios/Birthdays.xcodeproj" \
  -scheme Birthdays \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$project_root/config/ExportOptions.plist" \
  -allowProvisioningUpdates

print "IPA créée dans $export_path/Birthdays.ipa\n"
