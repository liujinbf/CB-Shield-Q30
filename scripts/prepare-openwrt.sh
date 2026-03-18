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

refresh_feeds() {
  local attempt
  local max_attempts=3
  local required_files=(
    "feeds/packages/lang/perl/perlver.mk"
    "feeds/packages/lang/python/python3-version.mk"
  )

  for attempt in $(seq 1 "$max_attempts"); do
    echo "[prepare] feeds update attempt ${attempt}/${max_attempts}"

    rm -rf feeds/packages feeds/luci feeds/routing feeds/telephony \
      feeds/passwall feeds/passwall_packages feeds/argon feeds/argon_config feeds/kwrt \
      feeds/*.index tmp/.packageinfo tmp/.packageauxvars tmp/.targetinfo

    if ./scripts/feeds update -a; then
      local missing=0
      local file
      for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
          echo "[prepare] missing required feed file: $file"
          missing=1
        fi
      done

      if [ "$missing" -eq 0 ]; then
        return 0
      fi
    fi

    echo "[prepare] feeds update incomplete, retrying..."
    sleep 5
  done

  echo "[prepare] feeds update failed after ${max_attempts} attempts"
  return 1
}

cd "$OPENWRT_DIR"
bash "$REPO_DIR/scripts/diy-part1.sh"
refresh_feeds
./scripts/feeds install -a
bash "$REPO_DIR/scripts/diy-part2.sh"

cp "$REPO_DIR/.config" "$OPENWRT_DIR/.config"
printf '\n# Profile override: %s\n' "$PROFILE" >> "$OPENWRT_DIR/.config"
cat "$PROFILE_FILE" >> "$OPENWRT_DIR/.config"
make defconfig
