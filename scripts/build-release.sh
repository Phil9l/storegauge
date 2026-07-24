#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Build a signed and notarized StoreGauge DMG.

Usage:
  ./scripts/build-release.sh [--version X.Y.Z] [--notary-profile NAME] [--output-dir PATH]

By default the script increments the patch version (1.0 -> 1.0.1) and the
build number, then writes the DMG to build/releases/. Use --version to select
an explicit marketing version. The build number is always incremented.

First-time setup:
  1. Install a Developer ID Application certificate in Xcode.
  2. Run: xcrun notarytool store-credentials storegauge-notary

Environment overrides:
  STOREGAUGE_SIGNING_IDENTITY  Exact Developer ID Application identity
  STOREGAUGE_NOTARY_PROFILE    notarytool Keychain profile name
EOF
}

project_dir="${0:A:h:h}"
project_file="$project_dir/StoreGauge/StoreGauge.xcodeproj/project.pbxproj"
xcode_project="$project_dir/StoreGauge/StoreGauge.xcodeproj"
scheme="StoreGauge"
team_id="75RZ97C25R"
requested_version=""
notary_profile="${STOREGAUGE_NOTARY_PROFILE:-storegauge-notary}"
output_dir="$project_dir/build/releases"

while (( $# > 0 )); do
  case "$1" in
    --version)
      (( $# >= 2 )) || { echo "Missing value for --version" >&2; exit 64; }
      requested_version="$2"
      shift 2
      ;;
    --notary-profile)
      (( $# >= 2 )) || { echo "Missing value for --notary-profile" >&2; exit 64; }
      notary_profile="$2"
      shift 2
      ;;
    --output-dir)
      (( $# >= 2 )) || { echo "Missing value for --output-dir" >&2; exit 64; }
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

cd "$project_dir"

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "Release builds require a clean Git working tree. Commit or stash changes first." >&2
  exit 65
fi

current_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' "$project_file" | head -n 1)"
current_build="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$project_file" | head -n 1)"

if [[ ! "$current_version" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || [[ ! "$current_build" =~ '^[0-9]+$' ]]; then
  echo "Could not read numeric MARKETING_VERSION and CURRENT_PROJECT_VERSION values." >&2
  exit 65
fi

if [[ -n "$requested_version" ]]; then
  if [[ ! "$requested_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "--version must use X.Y.Z format." >&2
    exit 64
  fi
  next_version="$requested_version"
else
  version_parts=("${(@s:.:)current_version}")
  version_major="${version_parts[1]}"
  version_minor="${version_parts[2]:-0}"
  version_patch="${version_parts[3]:-0}"
  next_version="$version_major.$version_minor.$(( version_patch + 1 ))"
fi
next_build="$(( current_build + 1 ))"

signing_identity="${STOREGAUGE_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  for identity_line in "${(@f)$(security find-identity -v -p codesigning)}"; do
    if [[ "$identity_line" =~ '"(Developer ID Application:[^"]+)"' ]]; then
      signing_identity="${match[1]}"
      break
    fi
  done
fi

if [[ -z "$signing_identity" ]]; then
  echo "No Developer ID Application certificate was found." >&2
  echo "Create one in Xcode > Settings > Accounts > Manage Certificates, then retry." >&2
  exit 69
fi

release_root="$(mktemp -d "${TMPDIR:-/tmp}/storegauge-release.XXXXXX")"
project_backup="$release_root/project.pbxproj"
archive_path="$release_root/StoreGauge.xcarchive"
export_dir="$release_root/export"
dmg_staging="$release_root/dmg"
export_options="$release_root/ExportOptions.plist"
version_changed=0
release_finished=0

cp "$project_file" "$project_backup"

cleanup() {
  exit_status=$?
  if (( version_changed == 1 && release_finished == 0 )); then
    cp "$project_backup" "$project_file"
    echo "Restored version numbers because the release did not complete." >&2
  fi
  if [[ -n "$release_root" && "$release_root" == "${TMPDIR:-/tmp}"/storegauge-release.* ]]; then
    rm -rf "$release_root"
  fi
  return $exit_status
}
trap cleanup EXIT INT TERM

CURRENT_VERSION="$current_version" NEXT_VERSION="$next_version" \
CURRENT_BUILD="$current_build" NEXT_BUILD="$next_build" \
perl -0pi -e '
  s/MARKETING_VERSION = \Q$ENV{CURRENT_VERSION}\E;/MARKETING_VERSION = $ENV{NEXT_VERSION};/g;
  s/CURRENT_PROJECT_VERSION = \Q$ENV{CURRENT_BUILD}\E;/CURRENT_PROJECT_VERSION = $ENV{NEXT_BUILD};/g;
' "$project_file"
version_changed=1

if ! rg -q "MARKETING_VERSION = $next_version;" "$project_file" || \
   ! rg -q "CURRENT_PROJECT_VERSION = $next_build;" "$project_file"; then
  echo "Failed to update project version numbers." >&2
  exit 70
fi

cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$team_id</string>
</dict>
</plist>
EOF

echo "Building StoreGauge $next_version ($next_build)…"
xcodebuild archive \
  -project "$xcode_project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates

app_path="$export_dir/StoreGauge.app"
if [[ ! -d "$app_path" ]]; then
  echo "The exported StoreGauge.app was not found at $app_path" >&2
  exit 70
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

mkdir -p "$dmg_staging"
ditto "$app_path" "$dmg_staging/StoreGauge.app"
ln -s /Applications "$dmg_staging/Applications"

mkdir -p "$output_dir"
final_dmg="$output_dir/StoreGauge-$next_version.dmg"
unsigned_dmg="$release_root/StoreGauge-$next_version.dmg"

hdiutil create \
  -volname "StoreGauge" \
  -srcfolder "$dmg_staging" \
  -format UDZO \
  -ov \
  "$unsigned_dmg"

codesign --force --timestamp --sign "$signing_identity" "$unsigned_dmg"

echo "Submitting the DMG to Apple's notary service…"
xcrun notarytool submit "$unsigned_dmg" \
  --keychain-profile "$notary_profile" \
  --wait

xcrun stapler staple "$unsigned_dmg"
xcrun stapler validate "$unsigned_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$unsigned_dmg"

ditto "$unsigned_dmg" "$final_dmg"
release_finished=1

echo
echo "Release ready: $final_dmg"
echo "Version updated: $current_version ($current_build) -> $next_version ($next_build)"
echo "Next: test the DMG, commit the version bump, then publish it and update the appcast."
