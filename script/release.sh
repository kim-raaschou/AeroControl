#!/bin/bash
#
# Build a versioned, distributable AeroControl release and generate its Homebrew
# cask — mirroring AeroSpace's release model (tag -> GitHub Release -> cask bump).
#
#   script/release.sh <version> [--publish]
#
#   <version>   e.g. 0.1.0-Beta  (the git tag becomes v<version>)
#   --publish   also create the GitHub Release and upload the zip via `gh`.
#               Omit it for a dry run that only builds the artifact + cask locally.
#
# Set ARCHS to override the build architecture(s):
#   ARCHS="arm64"            (default — macOS 26 is Apple-Silicon-era)
#   ARCHS="arm64 x86_64"     (universal, like AeroSpace)
#
# The release artifact and generated cask land in ./.release/ (git-ignored).
# The cask is meant to be committed to the separate tap repo
# kim-raaschou/homebrew-tap as Casks/aerocontrol.rb.

set -euo pipefail

APP_NAME="AeroControl"
REPO="kim-raaschou/AeroControl"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ $# -lt 1 ]; then
    echo "usage: script/release.sh <version> [--publish]" >&2
    exit 2
fi

VERSION="$1"
PUBLISH=0
[ "${2:-}" = "--publish" ] && PUBLISH=1

# Numeric part for Info.plist's CFBundleShortVersionString (Apple wants numeric):
# strip a trailing pre-release suffix like "-Beta".
SHORT_VERSION="${VERSION%%-*}"

TAG="v${VERSION}"
STAGE_NAME="${APP_NAME}-${TAG}"
OUT_DIR="${ROOT}/.release"
STAGE_DIR="${OUT_DIR}/${STAGE_NAME}"
APP_BUNDLE="${STAGE_DIR}/${APP_NAME}.app"
ZIP_PATH="${OUT_DIR}/${STAGE_NAME}.zip"
CASK_PATH="${OUT_DIR}/aerocontrol.rb"

ARCHS="${ARCHS:-arm64}"
ARCH_FLAGS=""
for a in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS --arch $a"; done

echo "==> Releasing ${APP_NAME} ${VERSION} (tag ${TAG}, short ${SHORT_VERSION}, archs: ${ARCHS})"

echo "==> Running tests"
swift test

echo "==> Building release binary"
# shellcheck disable=SC2086
swift build -c release --product "${APP_NAME}" ${ARCH_FLAGS}

# `swift build --arch a --arch b` writes a universal binary to .build/apple/...;
# a single-arch build writes to .build/release/. Resolve the actual binary path.
# shellcheck disable=SC2086
BIN_PATH="$(swift build -c release --product "${APP_NAME}" ${ARCH_FLAGS} --show-bin-path)/${APP_NAME}"
if [ ! -x "$BIN_PATH" ]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling ${APP_NAME}.app (version-stamped, ad-hoc signed)"
rm -rf "$STAGE_DIR"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
cp "$BIN_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
# Stamp the version into the bundle so plist, tag and cask never drift.
cp Packaging/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" \
    "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${SHORT_VERSION}" \
    "${APP_BUNDLE}/Contents/Info.plist"
# AeroControl's own display version string (v<version>, e.g. v0.1.0) shown in the menu.
/usr/libexec/PlistBuddy -c "Set :ACReleaseVersion ${TAG}" \
    "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :ACReleaseVersion string ${TAG}" \
    "${APP_BUNDLE}/Contents/Info.plist"
codesign --force --sign - "$APP_BUNDLE"

echo "==> Zipping ${ZIP_PATH}"
rm -f "$ZIP_PATH"
( cd "$OUT_DIR" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE_NAME" "$(basename "$ZIP_PATH")" )

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "==> sha256: ${SHA256}"

echo "==> Generating cask ${CASK_PATH}"
sed -e "s|__VERSION__|${VERSION}|g" -e "s|__SHA256__|${SHA256}|g" \
    Packaging/aerocontrol.rb.tmpl > "$CASK_PATH"

if [ "$PUBLISH" -eq 1 ]; then
    echo "==> Publishing GitHub Release ${TAG}"
    if ! git rev-parse "$TAG" >/dev/null 2>&1; then
        git tag "$TAG"
        git push origin "$TAG"
    fi
    gh release create "$TAG" "$ZIP_PATH" \
        --repo "$REPO" --title "$TAG" --notes "AeroControl ${VERSION}"
else
    echo "==> Dry run (no --publish): artifact + cask are in .release/"
fi

if [ "$PUBLISH" -eq 1 ]; then
    PUBLISH_NOTE=" (release already published)"
else
    PUBLISH_NOTE=""
fi

cat <<EOF

Done.

  Artifact : ${ZIP_PATH}
  Cask     : ${CASK_PATH}

Next steps:
  1. Copy ${CASK_PATH} to kim-raaschou/homebrew-tap as Casks/aerocontrol.rb
     and commit it${PUBLISH_NOTE}.
  2. Users then install with:
       brew install --cask kim-raaschou/tap/aerocontrol
EOF
