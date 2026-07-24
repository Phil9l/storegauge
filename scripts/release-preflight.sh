#!/bin/zsh
set -u

project_dir="${0:A:h:h}"
profile="${STOREGAUGE_NOTARY_PROFILE:-storegauge-notary}"
failures=0
warnings=0

pass() { echo "✓ $1"; }
fail() { echo "✗ $1" >&2; failures=$(( failures + 1 )); }
warn() { echo "! $1" >&2; warnings=$(( warnings + 1 )); }

cd "$project_dir" || exit 70

echo "StoreGauge release preflight"
echo

if xcodebuild -version >/dev/null 2>&1; then
  pass "Xcode command-line tools are available"
else
  fail "Xcode command-line tools are unavailable"
fi

identity_count="$(security find-identity -v -p codesigning 2>/dev/null | rg -c 'Developer ID Application:' || true)"
if (( identity_count > 0 )); then
  pass "Developer ID Application certificate is available"
else
  fail "No Developer ID Application certificate; create one in Xcode → Settings → Accounts"
fi

if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  pass "Notarization profile '$profile' works"
else
  fail "Notarization profile '$profile' is unavailable; run: xcrun notarytool store-credentials $profile"
fi

info_plist="$project_dir/StoreGauge/StoreGauge/Info.plist"
entitlements="$project_dir/StoreGauge/StoreGauge/StoreGauge.entitlements"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist" 2>/dev/null || true)"
feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist" 2>/dev/null || true)"

if [[ -n "$public_key" && "$feed_url" == https://* ]]; then
  pass "Sparkle public key and HTTPS feed are configured"
else
  fail "Sparkle SUPublicEDKey or SUFeedURL is missing"
fi

generate_keys="$project_dir/.build/sparkle-packages/artifacts/sparkle/Sparkle/bin/generate_keys"
if [[ -x "$generate_keys" ]]; then
  key_output="$("$generate_keys" --account storegauge -p 2>/dev/null || true)"
  keychain_public="$(print -r -- "$key_output" | rg -o '[A-Za-z0-9+/]{43}=' | tail -n 1)"
  if [[ "$keychain_public" == "$public_key" ]]; then
    pass "Sparkle Keychain private key matches the committed public key"
  else
    fail "Sparkle Keychain key for account 'storegauge' does not match SUPublicEDKey"
  fi
else
  warn "Sparkle tools are not resolved in .build; generate-appcast.sh will resolve them when needed"
fi

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$entitlements" 2>/dev/null | rg -q true &&
   /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-only' "$entitlements" 2>/dev/null | rg -q true; then
  pass "Sandbox permits API access and user-selected credential files"
else
  fail "Required network/file sandbox entitlements are missing"
fi

if plutil -lint "$info_plist" "$entitlements" >/dev/null &&
   xmllint --noout "$project_dir/docs/public/appcast.xml" >/dev/null 2>&1; then
  pass "Info.plist, entitlements, and appcast XML are valid"
else
  fail "A release plist or the appcast is invalid"
fi

if git diff --quiet && git diff --cached --quiet &&
   [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
  pass "Git working tree is clean"
else
  warn "Git working tree is not clean; build-release.sh will stop until changes are committed"
fi

echo
if (( failures > 0 )); then
  echo "Preflight failed with $failures blocking issue(s) and $warnings warning(s)." >&2
  exit 1
fi

echo "Preflight passed with $warnings warning(s)."
