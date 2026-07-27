#!/usr/bin/env bash
# Builds, signs, notarizes and packages Sono for distribution outside the App
# Store. One command: Scripts/release.sh
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login keychain.
#      Xcode → Settings → Accounts → your Apple ID → Manage Certificates →
#      + → Developer ID Application
#   2. Notary credentials stored in the keychain under the profile "sono-notary":
#      xcrun notarytool store-credentials sono-notary \
#        --apple-id "you@example.com" --team-id "TEAMID" \
#        --password "app-specific-password"      # appleid.apple.com → App-Specific Passwords
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Sono"
NOTARY_PROFILE="${NOTARY_PROFILE:-sono-notary}"
BUILD_DIR="$ROOT/build/release"
DIST_DIR="$ROOT/dist"

step() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }
fail() { printf "\n\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

# ─────────────────────────────────────────────────── preflight
step "Preflight"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)"
[ -n "$IDENTITY" ] || fail "No 'Developer ID Application' certificate found.
  Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
  (Apple Development certificates cannot be notarized.)"
echo "  signing identity: $IDENTITY"

TEAM_ID="$(echo "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p' || true)"
echo "  team: $TEAM_ID"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "No notary credentials stored for profile '$NOTARY_PROFILE'. Run:
  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --apple-id \"you@example.com\" --team-id \"$TEAM_ID\" --password \"app-specific-password\""
echo "  notary profile: $NOTARY_PROFILE"

[ -f "$ROOT/Vendor/sherpa/lib/libsherpa-onnx-c-api.dylib" ] \
  || fail "Vendored libraries missing. Run Scripts/fetch-sherpa.sh"

[ -x "$ROOT/Scripts/bin/sign_update" ] \
  || fail "Sparkle tools missing. Run Scripts/fetch-sparkle-tools.sh"

VERSION="$(grep -E "^\s+MARKETING_VERSION:" project.yml | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || true)"
[ -n "$VERSION" ] || fail "Could not read MARKETING_VERSION from project.yml"
# Sparkle compares sparkle:version against the INSTALLED app's CFBundleVersion,
# not against the marketing string. Writing "1.1.1" there while the installed
# build reported CFBundleVersion 2 made Sparkle read 1 < 2 and answer "up to
# date" for an update that was genuinely newer. This is the build number.
BUILD="$(grep -E "^\s+CURRENT_PROJECT_VERSION:" project.yml | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || true)"
[ -n "$BUILD" ] || fail "Could not read CURRENT_PROJECT_VERSION from project.yml"
echo "  version: $VERSION (build $BUILD)"

# ─────────────────────────────────────────────────── build
step "Building Release"
xcodegen generate >/dev/null
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
# MLX ships Swift macros, and Xcode refuses to run a package macro until it has
# been trusted in the UI. That prompt cannot appear in a script, so the flag is
# required here or every release fails on a machine that has not opened Xcode.
xcodebuild -project Sono.xcodeproj -scheme "$APP_NAME" -configuration Release \
  -skipMacroValidation \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build > "$BUILD_DIR/build.log" 2>&1 \
  || { tail -30 "$BUILD_DIR/build.log"; fail "Build failed — see $BUILD_DIR/build.log"; }

APP="$BUILD_DIR/$APP_NAME.app"
[ -d "$APP" ] || fail "Built app not found at $APP"
echo "  built: $APP"

# ─────────────────────────────────────────────────── sign
# Nested code must be signed BEFORE the bundle that contains it, innermost first,
# or the outer signature seals an unsigned binary and notarization rejects it.
step "Signing (inside out)"
while IFS= read -r dylib; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$dylib"
  echo "  signed: $(basename "$dylib")"
done < <(find "$APP/Contents/Frameworks" -name "*.dylib" -type f 2>/dev/null)

# Sparkle arrives pre-signed, and Xcode strips Headers/, PrivateHeaders/ and
# Modules/ when it embeds the framework. Those paths are still sealed in the
# original signature, so --deep --strict reports "a sealed resource is missing"
# and the release stops before it ever reaches Apple. Re-signing the framework
# writes a seal that matches what actually ships. Its own nested code goes
# first, for the same innermost-first reason as everything else here.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  for nested in \
    "$SPARKLE/Versions/Current/XPCServices/Downloader.xpc" \
    "$SPARKLE/Versions/Current/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/Current/Updater.app" \
    "$SPARKLE/Versions/Current/Autoupdate"; do
    [ -e "$nested" ] || continue
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$nested"
    echo "  signed: Sparkle/$(basename "$nested")"
  done
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$SPARKLE"
  echo "  signed: Sparkle.framework"
fi

codesign --force --timestamp --options runtime \
  --entitlements "$ROOT/Sono.entitlements" \
  --sign "$IDENTITY" "$APP"
echo "  signed: $APP_NAME.app"

step "Verifying signature"
# Not piped into sed: a pipeline reports the last command's status, so a failed
# verify used to look like success and the script sailed on.
if ! codesign --verify --deep --strict --verbose=2 "$APP" 2>&1; then
  fail "Signature verification failed. Nothing was submitted to Apple."
fi

# ─────────────────────────────────────────────────── package
step "Packaging DMG"
mkdir -p "$DIST_DIR"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"     # the drag-to-install gesture
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO \
  -quiet "$DMG"
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "  $DMG ($(du -h "$DMG" | cut -f1))"

# ─────────────────────────────────────────────────── notarize
step "Notarizing (Apple usually answers in 1–5 minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
  | tee "$DIST_DIR/notary.log" | sed 's/^/  /'
grep -q "status: Accepted" "$DIST_DIR/notary.log" || {
  ID="$(grep -m1 "id:" "$DIST_DIR/notary.log" | awk '{print $2}')"
  echo "  Fetching the rejection reason…"
  xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" | sed 's/^/  /'
  fail "Notarization rejected — see the log above"
}

step "Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG" | sed 's/^/  /'

# ─────────────────────────────────────────────────── verify like a user would
step "Gatekeeper assessment (what a customer's Mac will decide)"
spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'

# ─────────────────────────────────────────────────── appcast
# Signed with the EdDSA key in the login Keychain. Without this signature Sparkle
# refuses the download, which is what makes a hijacked domain harmless.
step "Signing for Sparkle and writing the appcast"
SIGNATURE_LINE="$("$ROOT/Scripts/bin/sign_update" "$DMG")"
[ -n "$SIGNATURE_LINE" ] || fail "sign_update produced nothing. Has generate_keys been run on this Mac?"
SIZE="$(stat -f%z "$DMG")"
PUBDATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
NOTES_URL="https://heysono.app/releases/notes-$VERSION.html"

APPCAST="$DIST_DIR/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sono</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="https://heysono.app/releases/$APP_NAME-$VERSION.dmg"
                 sparkle:version="$BUILD"
                 sparkle:shortVersionString="$VERSION"
                 $SIGNATURE_LINE
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
echo "  $APPCAST"

step "Done"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
cat <<SUMMARY

  file    $DMG
  size    $SIZE bytes
  sha256  $SHA

  To publish:
    1. upload $APP_NAME-$VERSION.dmg  →  https://heysono.app/releases/
    2. upload appcast.xml             →  https://heysono.app/appcast.xml
    3. write notes-$VERSION.html      →  https://heysono.app/releases/

  Existing users see the update within a day, or immediately via Check now.
  NOTE: the appcast must already be reachable, or nobody gets this release.
SUMMARY
