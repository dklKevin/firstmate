#!/usr/bin/env bash
# fm-install-no-mistakes.sh - install a pinned, verified no-mistakes build.
#
# Same pin/checksum discipline as fm-install-herdr.sh and
# fm-install-treehouse.sh: official release URL, exact asset, SHA-256, bounded
# download, post-install version check. Never a floating package-manager latest
# and never an unpinned curl|sh installer.
#
# Usage:
#   fm-install-no-mistakes.sh <destination-directory>
#
# Pins no-mistakes v1.53.0, a stable release at or above bootstrap's floor.
set -eu

FM_NO_MISTAKES_CI_VERSION=1.53.0
FM_NO_MISTAKES_CI_TAG="v${FM_NO_MISTAKES_CI_VERSION}"
# Bounded download ceiling (bytes). Official 1.53.0 archives are under 15 MiB.
FM_NO_MISTAKES_CI_MAX_BYTES=20000000
FM_NO_MISTAKES_CI_REPO=kunchenguid/no-mistakes

die() {
  printf 'fm-install-no-mistakes.sh: %s\n' "$*" >&2
  exit 1
}

DESTINATION=${1:?usage: fm-install-no-mistakes.sh <destination-directory>}

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "${os}-${arch}" in
  linux-x86_64)
    ARCHIVE=no-mistakes-${FM_NO_MISTAKES_CI_TAG}-linux-amd64.tar.gz
    SHA256=3e1a344b87d4f8e4789dc47817b38859ad8a18f9f5da0c51023aaa60997c81ca
    ;;
  linux-aarch64|linux-arm64)
    ARCHIVE=no-mistakes-${FM_NO_MISTAKES_CI_TAG}-linux-arm64.tar.gz
    SHA256=c79be23f70deae3f7b94a509d60664367f09376bb331f023dc4a76074d82f1e6
    ;;
  darwin-arm64)
    ARCHIVE=no-mistakes-${FM_NO_MISTAKES_CI_TAG}-darwin-arm64.tar.gz
    SHA256=5f5900020efa3bc60765e7ed2b409ec94b2412a8848d13bf85109bd37bd90764
    ;;
  darwin-x86_64)
    ARCHIVE=no-mistakes-${FM_NO_MISTAKES_CI_TAG}-darwin-amd64.tar.gz
    SHA256=5f63484ab4a631332fddfbc26c8435800463c6e17a78fe5c1449c3b220624ce9
    ;;
  *)
    die "unsupported platform ${os}-${arch}; official no-mistakes assets are linux/darwin amd64 and arm64"
    ;;
esac

URL="https://github.com/${FM_NO_MISTAKES_CI_REPO}/releases/download/${FM_NO_MISTAKES_CI_TAG}/${ARCHIVE}"
TMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fm-no-mistakes.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

printf 'fm-install-no-mistakes.sh: downloading %s from %s\n' "$ARCHIVE" "$URL" >&2
curl -fsSL --max-filesize "$FM_NO_MISTAKES_CI_MAX_BYTES" "$URL" -o "$TMP/$ARCHIVE" \
  || die "download failed for $URL (bounded at $FM_NO_MISTAKES_CI_MAX_BYTES bytes)"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256=$(sha256sum "$TMP/$ARCHIVE" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA256=$(shasum -a 256 "$TMP/$ARCHIVE" | awk '{print $1}')
else
  die "need sha256sum or shasum to verify the no-mistakes archive"
fi

[ "$ACTUAL_SHA256" = "$SHA256" ] || die "checksum mismatch for $ARCHIVE (expected $SHA256, got $ACTUAL_SHA256)"

tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
if [ -f "$TMP/no-mistakes" ]; then
  BIN="$TMP/no-mistakes"
else
  BIN=$(find "$TMP" -type f -name no-mistakes | head -n 1)
  [ -n "$BIN" ] || die "archive $ARCHIVE did not contain a no-mistakes binary"
fi

mkdir -p "$DESTINATION"
install -m 0755 "$BIN" "$DESTINATION/no-mistakes"

installed_version=$("$DESTINATION/no-mistakes" --version 2>/dev/null | tr -d '[:space:]')
case "$installed_version" in
  *"${FM_NO_MISTAKES_CI_VERSION}"*) ;;
  *)
    die "installed no-mistakes version is '${installed_version:-<empty>}', expected it to contain ${FM_NO_MISTAKES_CI_VERSION}"
    ;;
esac

printf 'fm-install-no-mistakes.sh: installed no-mistakes %s to %s\n' \
  "$installed_version" "$DESTINATION/no-mistakes" >&2
"$DESTINATION/no-mistakes" --version
