#!/usr/bin/env bash
# Builds a voicemode release: archive, sign, DMG, notarize when possible, Sparkle appcast.
#
#   scripts/release.sh [--version X.Y.Z] [--build-dir DIR] [--output-dir DIR] [--no-notarize]
#
# Two modes, picked automatically:
#   (a) a "Developer ID Application" identity and notarization credentials are available:
#       export with method developer-id, notarize the DMG with notarytool, staple it.
#   (b) otherwise: sign with the identity that is available (Apple Development locally),
#       skip notarization and warn. Release builds are never ad-hoc signed.
#
# Environment (all optional):
#   SIGN_IDENTITY             codesigning identity name or SHA-1; default: Developer ID
#                             Application, then Apple Development
#   DEVELOPMENT_TEAM          team ID; default: OU of the signing certificate
#   NOTARY_KEYCHAIN_PROFILE   notarytool keychain profile (default: voicemode-notary)
#   NOTARY_API_KEY_PATH       App Store Connect API key (.p8); used with the two below
#   NOTARY_API_KEY_ID
#   NOTARY_API_ISSUER_ID
#   SPARKLE_ED_KEY_FILE       private EdDSA key file; default: the login keychain item
#   SPARKLE_ED_PRIVATE_KEY    private EdDSA key as a string (CI)
#   SPARKLE_ACCOUNT           keychain account of the EdDSA key (default: ed25519)
#   SPARKLE_BIN               directory with generate_appcast
#   APPCAST_BASE              existing appcast.xml to extend (default: OUTPUT_DIR/appcast.xml)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="voicemode"
SCHEME="Voicemode"
PROJECT="$ROOT/voicemode.xcodeproj"
REPO_URL="https://github.com/vladislavkovalskyi/voicemode"

# DMG window, in points. Slots must match packaging/dmg/make-background.py. Finder counts the
# 32 pt title bar of macOS 26 in the window height, so 432 leaves 400 pt for the background.
DMG_WINDOW_W=660
DMG_WINDOW_H=432
DMG_ICON_SIZE=128
DMG_APP_X=170
DMG_APP_Y=180
DMG_APPLICATIONS_X=490
DMG_APPLICATIONS_Y=180

VERSION=""
BUILD_DIR="$ROOT/build/rel"
OUTPUT_DIR="$ROOT/build/release"
NOTARIZE_WANTED=1

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || die "--version needs a value"; VERSION="$2"; shift 2 ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --build-dir) [[ $# -ge 2 ]] || die "--build-dir needs a value"; BUILD_DIR="$2"; shift 2 ;;
        --output-dir) [[ $# -ge 2 ]] || die "--output-dir needs a value"; OUTPUT_DIR="$2"; shift 2 ;;
        --no-notarize) NOTARIZE_WANTED=0; shift ;;
        -h | --help) usage; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# ---------------------------------------------------------------------------------------------
bold "Inputs"

command -v xcodebuild >/dev/null || die "xcodebuild not found; install Xcode"
command -v xcodegen >/dev/null || die "xcodegen not found; install it with: brew install xcodegen"

if [[ -z "$VERSION" ]]; then
    VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
    [[ -n "$VERSION" ]] || die "MARKETING_VERSION not found in project.yml; pass --version"
fi
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-+.][0-9A-Za-z.]+)?$ ]] || die "version '$VERSION' is not X.Y or X.Y.Z"

[[ "$(git rev-parse --is-shallow-repository)" == "false" ]] \
    || die "shallow clone: the build number is the commit count; fetch full history (fetch-depth: 0)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
COMMIT="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    warn "working tree has uncommitted changes; build $BUILD_NUMBER will not match commit $COMMIT"
fi

info "version  $VERSION"
info "build    $BUILD_NUMBER ($COMMIT)"

# ---------------------------------------------------------------------------------------------
bold "Signing"

# Prints "SHA1<TAB>name" for the first valid identity whose name starts with $1.
find_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1	\2/p' \
        | awk -F'\t' -v prefix="$1" 'index($2, prefix) == 1 || $1 == prefix { print; exit }'
}

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    IDENTITY_LINE="$(find_identity "$SIGN_IDENTITY")"
    [[ -n "$IDENTITY_LINE" ]] || die "SIGN_IDENTITY '$SIGN_IDENTITY' is not a valid codesigning identity in the keychain"
else
    IDENTITY_LINE="$(find_identity "Developer ID Application")"
    [[ -n "$IDENTITY_LINE" ]] || IDENTITY_LINE="$(find_identity "Apple Development")"
fi
[[ -n "$IDENTITY_LINE" ]] || die "no codesigning identity found. Release builds are never ad-hoc signed:
       TCC permissions would reset on every update. Install a Developer ID Application or
       Apple Development certificate (docs/RELEASING.md)."

IDENTITY_SHA="${IDENTITY_LINE%%	*}"
IDENTITY_NAME="${IDENTITY_LINE#*	}"

TEAM_ID="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM_ID" ]]; then
    TEAM_ID="$(security find-certificate -a -Z -c "$IDENTITY_NAME" -p 2>/dev/null \
        | awk -v sha="$IDENTITY_SHA" '/^SHA-1 hash:/ { keep = ($3 == sha) } keep && !/^SHA-/' \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p')"
fi
[[ -n "$TEAM_ID" ]] || die "cannot read the team ID from '$IDENTITY_NAME'; set DEVELOPMENT_TEAM"

DEVELOPER_ID=0
[[ "$IDENTITY_NAME" == "Developer ID Application:"* ]] && DEVELOPER_ID=1

NOTARY_ARGS=()
if [[ $DEVELOPER_ID -eq 1 && $NOTARIZE_WANTED -eq 1 ]]; then
    if [[ -n "${NOTARY_API_KEY_PATH:-}" && -n "${NOTARY_API_KEY_ID:-}" && -n "${NOTARY_API_ISSUER_ID:-}" ]]; then
        [[ -f "$NOTARY_API_KEY_PATH" ]] || die "NOTARY_API_KEY_PATH does not point to a file"
        NOTARY_ARGS=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID")
        NOTARY_SOURCE="App Store Connect API key"
    else
        PROFILE="${NOTARY_KEYCHAIN_PROFILE:-voicemode-notary}"
        if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
            NOTARY_ARGS=(--keychain-profile "$PROFILE")
            NOTARY_SOURCE="keychain profile $PROFILE"
        fi
    fi
fi

if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    MODE="a"
    info "mode     (a) Developer ID, notarized via $NOTARY_SOURCE"
else
    MODE="b"
    info "mode     (b) signed, not notarized"
fi
info "identity $IDENTITY_NAME"
info "team     $TEAM_ID"

if [[ "$MODE" == "b" ]]; then
    if [[ $DEVELOPER_ID -eq 1 && $NOTARIZE_WANTED -eq 0 ]]; then
        reason="--no-notarize was passed"
    elif [[ $DEVELOPER_ID -eq 1 ]]; then
        reason="no notarization credentials (NOTARY_API_KEY_* or keychain profile ${NOTARY_KEYCHAIN_PROFILE:-voicemode-notary})"
    else
        reason="no Developer ID Application certificate"
    fi
    warn "this build will NOT be notarized: $reason.
         Gatekeeper blocks it on other Macs until the user clicks Open Anyway in
         System Settings > Privacy & Security, or runs
         xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
fi

# ---------------------------------------------------------------------------------------------
bold "Project"

xcodegen generate --quiet
info "generated $(basename "$PROJECT")"

if ! xcrun -f metal >/dev/null 2>&1; then
    info "Metal Toolchain missing; downloading it: xcodebuild -downloadComponent MetalToolchain"
    xcodebuild -downloadComponent MetalToolchain
fi
info "metal    $(xcrun -f metal)"

# ---------------------------------------------------------------------------------------------
bold "Archive"

ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

XCODEBUILD_LOG="$BUILD_DIR/archive.log"
info "log      $XCODEBUILD_LOG"
if ! xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY_NAME" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    >"$XCODEBUILD_LOG" 2>&1; then
    grep -E "error:|BUILD FAILED|ARCHIVE FAILED" "$XCODEBUILD_LOG" | tail -30 >&2 || true
    die "xcodebuild archive failed; full log: $XCODEBUILD_LOG"
fi
info "archive  $ARCHIVE"

# ---------------------------------------------------------------------------------------------
bold "Export"

mkdir -p "$EXPORT_DIR"
if [[ $DEVELOPER_ID -eq 1 ]]; then
    EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
    cat >"$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$IDENTITY_SHA</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST
    if ! xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        >"$BUILD_DIR/export.log" 2>&1; then
        tail -30 "$BUILD_DIR/export.log" >&2
        die "xcodebuild -exportArchive failed; full log: $BUILD_DIR/export.log"
    fi
    info "exported with method developer-id"
else
    ditto "$ARCHIVE/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
    info "copied the app out of the archive"
fi
APP="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP" ]] || die "exported app not found at $APP"

TIMESTAMP_ARGS=()
[[ $DEVELOPER_ID -eq 1 ]] && TIMESTAMP_ARGS=(--timestamp)

signed_by_identity() { codesign -dvv "$1" 2>&1 | grep -qxF "Authority=$IDENTITY_NAME"; }

# Sparkle ships its helpers ad-hoc signed, and Xcode re-signs only the framework when it embeds
# it. Re-sign the helpers as Sparkle's documentation describes, then the framework and the app.
SPARKLE_VERSION_DIR="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
SPARKLE_HELPERS=()
if [[ -d "$SPARKLE_VERSION_DIR" ]]; then
    for helper in "$SPARKLE_VERSION_DIR"/XPCServices/*.xpc "$SPARKLE_VERSION_DIR/Autoupdate" "$SPARKLE_VERSION_DIR/Updater.app"; do
        [[ -e "$helper" ]] && SPARKLE_HELPERS+=("$helper")
    done
    RESIGN=0
    for helper in "${SPARKLE_HELPERS[@]+"${SPARKLE_HELPERS[@]}"}"; do
        signed_by_identity "$helper" || RESIGN=1
    done
    if [[ $RESIGN -eq 1 ]]; then
        for helper in "${SPARKLE_HELPERS[@]}"; do
            extra=()
            [[ "$(basename "$helper")" == "Downloader.xpc" ]] && extra=(--preserve-metadata=entitlements)
            codesign --force --sign "$IDENTITY_SHA" --options runtime \
                "${TIMESTAMP_ARGS[@]+"${TIMESTAMP_ARGS[@]}"}" "${extra[@]+"${extra[@]}"}" "$helper"
        done
        codesign --force --sign "$IDENTITY_SHA" --options runtime \
            "${TIMESTAMP_ARGS[@]+"${TIMESTAMP_ARGS[@]}"}" "$APP/Contents/Frameworks/Sparkle.framework"
        codesign --force --sign "$IDENTITY_SHA" --options runtime \
            "${TIMESTAMP_ARGS[@]+"${TIMESTAMP_ARGS[@]}"}" --preserve-metadata=entitlements,requirements,flags "$APP"
        info "re-signed Sparkle helpers: $(for h in "${SPARKLE_HELPERS[@]}"; do basename "$h"; done | tr '\n' ' ')"
    fi
fi

# ---------------------------------------------------------------------------------------------
bold "Verify app"

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
[[ "$(plist_get CFBundleShortVersionString)" == "$VERSION" ]] || die "CFBundleShortVersionString is '$(plist_get CFBundleShortVersionString)', expected $VERSION"
[[ "$(plist_get CFBundleVersion)" == "$BUILD_NUMBER" ]] || die "CFBundleVersion is '$(plist_get CFBundleVersion)', expected $BUILD_NUMBER"
info "Info.plist $VERSION ($BUILD_NUMBER), $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

NESTED=("$APP/Contents/Frameworks"/* "${SPARKLE_HELPERS[@]+"${SPARKLE_HELPERS[@]}"}")
for code in "${NESTED[@]}"; do
    [[ -e "$code" ]] || continue
    signed_by_identity "$code" || die "$(basename "$code") is not signed by $IDENTITY_NAME"
done
info "nested code signed by the same identity: $(for c in "${NESTED[@]}"; do basename "$c"; done | tr '\n' ' ')"

SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
grep -qxF "Authority=$IDENTITY_NAME" <<<"$SIGNATURE" || die "app is not signed by $IDENTITY_NAME"
grep -q "flags=.*runtime" <<<"$SIGNATURE" || die "hardened runtime is off"
grep -E "^(Authority|TeamIdentifier|Timestamp)=" <<<"$SIGNATURE" | sed 's/^/    /'

ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
grep -q "com.apple.security.device.audio-input" <<<"$ENTITLEMENTS" || die "audio-input entitlement is missing"
if grep -q "com.apple.security.get-task-allow" <<<"$ENTITLEMENTS"; then
    die "get-task-allow entitlement present; this is a debug-signed build"
fi
info "entitlements ok, hardened runtime on"

if [[ "$(plist_get SUPublicEDKey)" == "REPLACE_WITH_SPARKLE_PUBLIC_KEY" ]]; then
    warn "SUPublicEDKey is still the placeholder; Sparkle stays off in this build"
fi

if spctl --status 2>/dev/null | grep -q disabled; then
    info "Gatekeeper assessments are disabled on this Mac, so spctl accepts anything here"
fi
if SPCTL_OUT="$(spctl -a -vv -t exec "$APP" 2>&1)"; then
    printf '%s\n' "$SPCTL_OUT" | sed 's/^/    /'
else
    printf '%s\n' "$SPCTL_OUT" | sed 's/^/    /'
    if [[ "$MODE" == "a" ]]; then
        info "(expected before notarization)"
    else
        info "(informational: Gatekeeper rejects builds that are not notarized)"
    fi
fi

# ---------------------------------------------------------------------------------------------
bold "DMG"

if ! command -v create-dmg >/dev/null; then
    command -v brew >/dev/null || die "create-dmg not found and Homebrew is missing; install create-dmg"
    info "create-dmg not found; installing it: brew install create-dmg"
    brew install create-dmg
fi

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG="$OUTPUT_DIR/$DMG_NAME"
DMG_STABLE="$OUTPUT_DIR/$APP_NAME.dmg"
STAGING="$BUILD_DIR/dmg-root"
rm -rf "$STAGING" "$DMG" "$DMG_STABLE" "$OUTPUT_DIR/$DMG_NAME.sha256"
rm -f "$OUTPUT_DIR"/rw.*."$DMG_NAME"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"

BACKGROUND="$BUILD_DIR/background.tiff"
tiffutil -cathidpicheck packaging/dmg/background.png packaging/dmg/background@2x.png -out "$BACKGROUND" >/dev/null 2>&1 \
    || die "tiffutil could not combine packaging/dmg/background.png and background@2x.png"

VOLICON_ARGS=()
ICONSET="$BUILD_DIR/$APP_NAME.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp App/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
if command -v SetFile >/dev/null && iconutil -c icns -o "$BUILD_DIR/volume.icns" "$ICONSET" 2>/dev/null; then
    VOLICON_ARGS=(--volicon "$BUILD_DIR/volume.icns")
fi

# Finder lays the window out through AppleScript, which now and then times out.
attempt=1
until create-dmg \
    --volname "$APP_NAME" \
    "${VOLICON_ARGS[@]+"${VOLICON_ARGS[@]}"}" \
    --background "$BACKGROUND" \
    --window-pos 200 140 \
    --window-size "$DMG_WINDOW_W" "$DMG_WINDOW_H" \
    --icon-size "$DMG_ICON_SIZE" \
    --text-size 13 \
    --icon "$APP_NAME.app" "$DMG_APP_X" "$DMG_APP_Y" \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link "$DMG_APPLICATIONS_X" "$DMG_APPLICATIONS_Y" \
    --format ULMO \
    --no-internet-enable \
    --hdiutil-quiet \
    "$DMG" "$STAGING" >"$BUILD_DIR/create-dmg.log" 2>&1; do
    rm -f "$OUTPUT_DIR"/rw.*."$DMG_NAME" "$DMG"
    if [[ $attempt -ge 3 ]]; then
        tail -20 "$BUILD_DIR/create-dmg.log" >&2
        die "create-dmg failed $attempt times; full log: $BUILD_DIR/create-dmg.log"
    fi
    warn "create-dmg failed (attempt $attempt), retrying"
    attempt=$((attempt + 1))
    sleep 5
done

if [[ "$MODE" == "a" ]]; then
    codesign --force --sign "$IDENTITY_SHA" --timestamp "$DMG"
else
    codesign --force --sign "$IDENTITY_SHA" "$DMG"
fi
codesign --verify --strict "$DMG"
hdiutil verify -quiet "$DMG"
info "signed and verified $DMG_NAME"

# ---------------------------------------------------------------------------------------------
if [[ "$MODE" == "a" ]]; then
    bold "Notarize"

    NOTARY_JSON="$BUILD_DIR/notary.json"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait --timeout 2h --output-format json >"$NOTARY_JSON" \
        || true
    NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_JSON" 2>/dev/null || echo unknown)"
    NOTARY_ID="$(plutil -extract id raw -o - "$NOTARY_JSON" 2>/dev/null || echo "")"
    info "submission ${NOTARY_ID:-?}: $NOTARY_STATUS"
    if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
        if [[ -n "$NOTARY_ID" ]]; then
            xcrun notarytool log "$NOTARY_ID" "${NOTARY_ARGS[@]}" >&2 || true
        else
            cat "$NOTARY_JSON" >&2 || true
        fi
        die "notarization failed"
    fi

    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | sed 's/^/    /'
    spctl -a -vv -t exec "$APP" 2>&1 | sed 's/^/    /' || true
fi

cp "$DMG" "$DMG_STABLE"
SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$DMG_NAME" >"$OUTPUT_DIR/$DMG_NAME.sha256"

# ---------------------------------------------------------------------------------------------
bold "Sparkle appcast"

APPCAST="$OUTPUT_DIR/appcast.xml"
APPCAST_STATUS="skipped"

GENERATE_APPCAST=""
for candidate in \
    "${SPARKLE_BIN:+$SPARKLE_BIN/generate_appcast}" \
    "$(command -v generate_appcast 2>/dev/null || true)" \
    "$BUILD_DIR/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        GENERATE_APPCAST="$candidate"
        break
    fi
done

SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ed25519}"
KEY_ARGS=()
KEY_STDIN=""
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
    [[ -f "$SPARKLE_ED_KEY_FILE" ]] || die "SPARKLE_ED_KEY_FILE does not point to a file"
    KEY_ARGS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
elif [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    KEY_ARGS=(--ed-key-file -)
    KEY_STDIN="$SPARKLE_ED_PRIVATE_KEY"
elif security find-generic-password -s "https://sparkle-project.org" -a "$SPARKLE_ACCOUNT" >/dev/null 2>&1; then
    KEY_ARGS=(--account "$SPARKLE_ACCOUNT")
fi

if [[ -z "$GENERATE_APPCAST" ]]; then
    warn "generate_appcast not found; appcast skipped (set SPARKLE_BIN)"
elif [[ ${#KEY_ARGS[@]} -eq 0 ]]; then
    warn "no Sparkle EdDSA private key (SPARKLE_ED_KEY_FILE, SPARKLE_ED_PRIVATE_KEY or keychain); appcast skipped"
elif [[ "$(plist_get SUPublicEDKey)" == "REPLACE_WITH_SPARKLE_PUBLIC_KEY" ]]; then
    warn "SUPublicEDKey in project.yml is the placeholder; appcast skipped"
else
    APPCAST_DIR="$BUILD_DIR/appcast"
    rm -rf "$APPCAST_DIR"
    mkdir -p "$APPCAST_DIR"
    BASE="${APPCAST_BASE:-$APPCAST}"
    if [[ -f "$BASE" ]]; then
        cp "$BASE" "$APPCAST_DIR/appcast.xml"
        info "extending $BASE"
    fi
    cp "$DMG" "$APPCAST_DIR/$DMG_NAME"
    GENERATE_ARGS=(
        "${KEY_ARGS[@]}"
        --download-url-prefix "$REPO_URL/releases/download/v$VERSION/"
        --full-release-notes-url "$REPO_URL/releases"
        --link "$REPO_URL"
        --maximum-deltas 0
        "$APPCAST_DIR"
    )
    if [[ -n "$KEY_STDIN" ]]; then
        printf '%s' "$KEY_STDIN" | "$GENERATE_APPCAST" "${GENERATE_ARGS[@]}"
    else
        "$GENERATE_APPCAST" "${GENERATE_ARGS[@]}"
    fi
    cp "$APPCAST_DIR/appcast.xml" "$APPCAST"
    grep -q "sparkle:edSignature" "$APPCAST" || die "appcast has no EdDSA signature"
    APPCAST_STATUS="$APPCAST"
fi

# Read by the CI steps that publish the release.
{
    printf 'VERSION=%q\n' "$VERSION"
    printf 'BUILD_NUMBER=%q\n' "$BUILD_NUMBER"
    printf 'MODE=%q\n' "$MODE"
    printf 'NOTARIZED=%q\n' "$([[ "$MODE" == "a" ]] && echo true || echo false)"
    printf 'DMG=%q\n' "$DMG"
    printf 'DMG_STABLE=%q\n' "$DMG_STABLE"
    printf 'SHA256=%q\n' "$SHA256"
    printf 'APPCAST_UPDATED=%q\n' "$([[ "$APPCAST_STATUS" != "skipped" ]] && echo true || echo false)"
} >"$OUTPUT_DIR/release.env"

# ---------------------------------------------------------------------------------------------
bold "Done"

DMG_SIZE="$(du -h "$DMG" | awk '{print $1}')"
info "mode       ($MODE) $([[ "$MODE" == "a" ]] && echo "notarized and stapled" || echo "NOT notarized")"
info "version    $VERSION ($BUILD_NUMBER)"
info "identity   $IDENTITY_NAME"
info "dmg        $DMG ($DMG_SIZE)"
info "latest     $DMG_STABLE"
info "sha256     $SHA256"
info "appcast    $APPCAST_STATUS"
if [[ "$MODE" == "b" ]]; then
    warn "not notarized; see docs/RELEASING.md for what users see and how to open it"
fi
