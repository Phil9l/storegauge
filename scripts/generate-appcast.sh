#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 <directory-containing-signed-dmg-or-zip> <github-release-tag>" >&2
  echo "Example: $0 /tmp/storegauge-release v1.0.0" >&2
  exit 64
fi

release_dir="$1"
release_tag="$2"
if [[ ! -d "$release_dir" ]]; then
  echo "Release directory does not exist: $release_dir" >&2
  exit 66
fi

project_dir="${0:A:h:h}"
package_dir="$project_dir/.build/sparkle-packages"
sparkle_tool="$package_dir/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [[ ! -x "$sparkle_tool" ]]; then
  xcodebuild -resolvePackageDependencies \
    -project "$project_dir/StoreGauge/StoreGauge.xcodeproj" \
    -scheme StoreGauge \
    -clonedSourcePackagesDirPath "$package_dir"
fi

cp "$project_dir/docs/public/appcast.xml" "$release_dir/appcast.xml"

"$sparkle_tool" \
  --account storegauge \
  --download-url-prefix "https://github.com/Phil9l/storegauge/releases/download/$release_tag/" \
  --link "https://phil9l.github.io/storegauge/" \
  --maximum-versions 5 \
  "$release_dir"

cp "$release_dir/appcast.xml" "$project_dir/docs/public/appcast.xml"

echo "Updated $project_dir/docs/public/appcast.xml"
echo "Commit and push the appcast only after its referenced release assets are public."
