#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <openwrt_dir> <profile>"
  exit 1
fi

OPENWRT_DIR="$(cd "$1" && pwd)"
PROFILE="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_FILE="$REPO_DIR/profiles/${PROFILE}.config"

if [ ! -d "$OPENWRT_DIR" ]; then
  echo "openwrt dir not found: $OPENWRT_DIR"
  exit 1
fi

if [ ! -f "$PROFILE_FILE" ]; then
  echo "profile file not found: $PROFILE_FILE"
  exit 1
fi

export GITHUB_WORKSPACE="$REPO_DIR"

cp "$REPO_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf.default"

cd "$OPENWRT_DIR"
bash "$REPO_DIR/scripts/diy-part1.sh"
./scripts/feeds update -a
./scripts/feeds install -a
bash "$REPO_DIR/scripts/diy-part2.sh"

cp "$REPO_DIR/.config" "$OPENWRT_DIR/.config"
printf '\n# Profile override: %s\n' "$PROFILE" >> "$OPENWRT_DIR/.config"
cat "$PROFILE_FILE" >> "$OPENWRT_DIR/.config"
make defconfig
