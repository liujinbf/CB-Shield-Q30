#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$REPO_ROOT/.work"
OVERLAY_ARCHIVE="$WORK_DIR/cbshield-openwrtai-overlay.tgz"
OVERLAY_MANIFEST="$WORK_DIR/openwrtai-overlay.manifest"
RUNTIME_ARCHIVE="$WORK_DIR/cbshield-kwrt-runtime.tgz"
RUNTIME_INSTALLER="$WORK_DIR/cbshield-kwrt-install.sh"
RUNTIME_MANIFEST="$WORK_DIR/kwrt-runtime.manifest"
DELIVERY_ARCHIVE="$WORK_DIR/cbshield-kwrt-runtime-bundle.tgz"

bash "$SCRIPT_DIR/build-openwrtai-overlay.sh"

cp "$OVERLAY_ARCHIVE" "$RUNTIME_ARCHIVE"
cp "$SCRIPT_DIR/cbshield-kwrt-install.sh" "$RUNTIME_INSTALLER"
cp "$OVERLAY_MANIFEST" "$RUNTIME_MANIFEST"

chmod +x "$RUNTIME_INSTALLER"

tar -czf "$DELIVERY_ARCHIVE" \
    -C "$WORK_DIR" \
    "$(basename "$RUNTIME_ARCHIVE")" \
    "$(basename "$RUNTIME_INSTALLER")" \
    "$(basename "$RUNTIME_MANIFEST")"

sha256sum "$RUNTIME_ARCHIVE" "$RUNTIME_INSTALLER" "$DELIVERY_ARCHIVE" > "$WORK_DIR/kwrt-runtime.SHA256SUMS"

echo "runtime_archive=$RUNTIME_ARCHIVE"
echo "runtime_installer=$RUNTIME_INSTALLER"
echo "runtime_manifest=$RUNTIME_MANIFEST"
echo "delivery_archive=$DELIVERY_ARCHIVE"
