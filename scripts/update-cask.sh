#!/usr/bin/env bash
# Writes version and sha256 of a built DMG into the Homebrew cask.
#
#   scripts/update-cask.sh [DMG] [--version X.Y.Z] [--cask PATH]
#   scripts/update-cask.sh --from-release X.Y.Z [--cask PATH]
#
# DMG      default: the newest build/release/voicemode-*.dmg
# --from-release downloads voicemode-X.Y.Z.dmg from the GitHub release, so the checksum
#          matches what users download when CI built the release
# version  default: taken from the file name voicemode-X.Y.Z.dmg, or from the app inside
# PATH     default: packaging/homebrew/voicemode.rb; pass Casks/voicemode.rb of a
#          vladislavkovalskyi/homebrew-tap checkout to update the tap

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DMG=""
VERSION=""
FROM_RELEASE=""
CASK="$ROOT/packaging/homebrew/voicemode.rb"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || die "--version needs a value"; VERSION="${2#v}"; shift 2 ;;
        --cask) [[ $# -ge 2 ]] || die "--cask needs a value"; CASK="$2"; shift 2 ;;
        --from-release) [[ $# -ge 2 ]] || die "--from-release needs a version"; FROM_RELEASE="${2#v}"; shift 2 ;;
        -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown argument: $1" ;;
        *) [[ -z "$DMG" ]] || die "one DMG at a time"; DMG="$1"; shift ;;
    esac
done

if [[ -n "$FROM_RELEASE" ]]; then
    [[ -z "$DMG" ]] || die "pass either a DMG or --from-release"
    VERSION="$FROM_RELEASE"
    DMG="$(mktemp -d -t voicemode-cask)/voicemode-$VERSION.dmg"
    url="https://github.com/vladislavkovalskyi/voicemode/releases/download/v$VERSION/voicemode-$VERSION.dmg"
    printf 'download %s\n' "$url"
    curl -fL --progress-bar -o "$DMG" "$url" || die "download failed: $url"
fi

if [[ -z "$DMG" ]]; then
    DMG="$(ls -t "$ROOT"/build/release/voicemode-*.dmg 2>/dev/null | head -1 || true)"
    [[ -n "$DMG" ]] || die "no build/release/voicemode-*.dmg; run scripts/release.sh or pass a DMG"
fi
[[ -f "$DMG" ]] || die "DMG not found: $DMG"
[[ -f "$CASK" ]] || die "cask not found: $CASK"

if [[ -z "$VERSION" ]]; then
    name="$(basename "$DMG")"
    if [[ "$name" =~ ^voicemode-(.+)\.dmg$ ]]; then
        VERSION="${BASH_REMATCH[1]}"
    else
        mount="$(mktemp -d -t voicemode-cask)"
        hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mount" "$DMG" >/dev/null
        VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount/voicemode.app/Contents/Info.plist" 2>/dev/null || true)"
        hdiutil detach -quiet "$mount" || true
        rmdir "$mount" 2>/dev/null || true
    fi
fi
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-+.][0-9A-Za-z.]+)?$ ]] || die "cannot tell the version of $DMG; pass --version"

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

sed -i '' -E \
    -e "s/^([[:space:]]*version )\"[^\"]*\"/\1\"$VERSION\"/" \
    -e "s/^([[:space:]]*sha256 )\"[^\"]*\"/\1\"$SHA256\"/" \
    "$CASK"

grep -q "version \"$VERSION\"" "$CASK" || die "version line not found in $CASK"
grep -q "sha256 \"$SHA256\"" "$CASK" || die "sha256 line not found in $CASK"

printf 'cask     %s\nversion  %s\nsha256   %s\n' "$CASK" "$VERSION" "$SHA256"
printf 'url      https://github.com/vladislavkovalskyi/voicemode/releases/download/v%s/voicemode-%s.dmg\n' "$VERSION" "$VERSION"
