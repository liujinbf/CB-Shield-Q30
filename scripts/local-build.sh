#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-stable}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_ROOT="${WORK_ROOT:-$REPO_DIR/.work}"
OPENWRT_DIR="${OPENWRT_DIR:-$WORK_ROOT/openwrt}"
REPO_URL="${REPO_URL:-https://github.com/openwrt/openwrt.git}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-23.05}"

mkdir -p "$WORK_ROOT"

if [ ! -d "$OPENWRT_DIR/.git" ]; then
  git clone --depth 1 "$REPO_URL" -b "$REPO_BRANCH" "$OPENWRT_DIR"
fi

bash "$REPO_DIR/scripts/prepare-openwrt.sh" "$OPENWRT_DIR" "$PROFILE"
bash "$REPO_DIR/scripts/package-preflight.sh" "$OPENWRT_DIR"

cd "$OPENWRT_DIR"
make download -j"$(nproc)"
find dl -size -1024c -delete
make -j"$(nproc)" || make -j1 V=s

OUT_DIR="$REPO_DIR/artifacts/$PROFILE"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
find "$OPENWRT_DIR/bin/targets" -type f \( -name "*jcg_q30-pro*factory.bin" -o -name "*jcg_q30-pro*sysupgrade.bin" -o -name "*jcg_q30-pro*.manifest" \) -exec cp -f {} "$OUT_DIR/" \;
(
  cd "$OUT_DIR"
  sha256sum *.bin > SHA256SUMS
)

echo "artifacts: $OUT_DIR"
