#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
if [[ "$MODE" != "build" && "$MODE" != "prepare" ]]; then
  echo "usage: $0 [build|prepare]"
  exit 1
fi

REPO_DIR="${REPO_DIR:-/repo}"
WORKDIR_ROOT="${WORKDIR_ROOT:-/workdir}"
OPENWRT_DIR="${OPENWRT_DIR:-$WORKDIR_ROOT/openwrt}"
REPO_URL="${REPO_URL:-https://github.com/openwrt/openwrt.git}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-25.12}"
TARGET_NAME="${TARGET_NAME:-mediatek_filogic}"
KWRT_SRC_DIR="${KWRT_SRC_DIR:-${REPO_DIR}/Kwrt-src}"
KWRT_SRC_URL="${KWRT_SRC_URL:-https://github.com/kiddin9/Kwrt.git}"
KWRT_SRC_BRANCH="${KWRT_SRC_BRANCH:-25.12}"
LOG_FILE="${REPO_DIR}/logs/build-kwrt-passwall-docker.log"
OUT_DIR="${REPO_DIR}/artifacts/kwrt-passwall-firmware"

mkdir -p "${REPO_DIR}/logs" "${REPO_DIR}/artifacts" "${WORKDIR_ROOT}"
: > "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

export DEBIAN_FRONTEND=noninteractive
export GITHUB_WORKSPACE="${REPO_DIR}"
export FORCE_UNSAFE_CONFIGURE=1

install_build_deps() {
  if ! command -v apt-get >/dev/null 2>&1; then
    return 0
  fi

  local sudo_cmd=""
  local packages=(
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
    gettext git libncurses-dev libssl-dev python3-setuptools rsync swig
    unzip zlib1g-dev file wget llvm python3-pyelftools libpython3-dev
    qemu-utils ccache libelf-dev device-tree-compiler libgmp-dev
    libmpc-dev libfuse-dev curl ca-certificates patch
  )
  local installable=()
  local package

  if command -v sudo >/dev/null 2>&1; then
    sudo_cmd="sudo"
  fi

  ${sudo_cmd} apt-get -qq update

  for package in "${packages[@]}"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      installable+=("$package")
    else
      echo "[deps] skip unavailable package: $package"
    fi
  done

  ${sudo_cmd} apt-get -qq install -y "${installable[@]}"
}

normalize_unix_files() {
  local file
  for file in "$@"; do
    [ -f "$file" ] || continue
    sed -i 's/\r$//' "$file"
  done
}

prepare_kwrt_source_dir() {
  if [ -d "${KWRT_SRC_DIR}/devices/common" ] && [ -d "${KWRT_SRC_DIR}/devices/${TARGET_NAME}" ]; then
    return 0
  fi

  KWRT_SRC_DIR="${WORKDIR_ROOT}/kwrt-src"
  rm -rf "${KWRT_SRC_DIR}"
  git clone --depth 1 -b "${KWRT_SRC_BRANCH}" --filter=blob:none --sparse "${KWRT_SRC_URL}" "${KWRT_SRC_DIR}"
  (
    cd "${KWRT_SRC_DIR}"
    git sparse-checkout init --cone
    git sparse-checkout set devices/common "devices/${TARGET_NAME}"
  )
}

git_clone_path() {
  trap 'rm -rf "$tmpdir"' EXIT
  local branch="$1"
  local rurl="$2"
  local mv_mode="${3:-}"
  if [ "$mv_mode" = "mv" ]; then
    shift 3
  else
    shift 2
  fi

  local rootdir="$PWD"
  local tmpdir
  tmpdir="$(mktemp -d)"

  if [ "${#branch}" -lt 10 ]; then
    git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$rurl" "$tmpdir"
    cd "$tmpdir"
  else
    git clone --filter=blob:none --sparse "$rurl" "$tmpdir"
    cd "$tmpdir"
    git checkout "$branch"
  fi

  git sparse-checkout init --cone
  git sparse-checkout set "$@"

  if [ "$mv_mode" = "mv" ]; then
    mkdir -p "$rootdir/$1"
    mv -n "$1"/. "$rootdir/$1"/
  else
    cp -rn ./* "$rootdir"/
  fi
  cd "$rootdir"
}

prepare_kwrt_tree() {
  cd "${OPENWRT_DIR}"
  prepare_kwrt_source_dir

  mkdir -p devices
  cp -rf "${KWRT_SRC_DIR}/devices/common" devices/
  cp -rf "${KWRT_SRC_DIR}/devices/${TARGET_NAME}" devices/

  normalize_unix_files \
    devices/common/diy.sh \
    devices/${TARGET_NAME}/diy.sh \
    "${REPO_DIR}/scripts/build-openwrtai-overlay.sh" \
    "${REPO_DIR}/scripts/prepare-openwrt.sh" \
    "${REPO_DIR}/scripts/diy-part2.sh"

  cp -rf devices/common/. .
  cp -rf devices/${TARGET_NAME}/. .

  export -f git_clone_path
  export REPO_TOKEN="${REPO_TOKEN:-}"
  export TARGET="${TARGET_NAME}"

  bash "devices/common/diy.sh"

  cp -f "devices/common/.config" .config
  if [ -f "devices/${TARGET_NAME}/.config" ]; then
    printf '\n' >> .config
    cat "devices/${TARGET_NAME}/.config" >> .config
  fi

  if [ -f "devices/${TARGET_NAME}/diy.sh" ]; then
    bash "devices/${TARGET_NAME}/diy.sh"
  fi

  local safe_revision
  safe_revision="$(date +%Y%m%d)"
  sed -i \
    -e "/\(# \)\?REVISION:=/c\\REVISION:=${safe_revision}" \
    -e '/VERSION_CODE:=/c\\VERSION_CODE:=$(REVISION)' \
    include/version.mk

  cp -Rf ./diy/* ./ || true

  cp -rn devices/common/patches "devices/${TARGET_NAME}/" || true

  if compgen -G "devices/${TARGET_NAME}/patches/*.bin.patch" >/dev/null; then
    git apply "devices/${TARGET_NAME}"/patches/*.bin.patch
  fi

  find "devices/${TARGET_NAME}/patches" -maxdepth 1 -type f -name '*.revert.patch' -print0 \
    | sort -z \
    | xargs -r -0 -I % -n 1 sh -c "patch -d './' -R --no-backup-if-mismatch -p1 -F 1 --ignore-whitespace -i '%'"

  find "devices/${TARGET_NAME}/patches" -maxdepth 1 -type f -name '*.patch' ! -name '*.revert.patch' ! -name '*.bin.patch' -print0 \
    | sort -z \
    | xargs -r -0 -I % -n 1 sh -c "patch -d './' --no-backup-if-mismatch -p1 -F 1 --ignore-whitespace -i '%'"
}

inject_cbshield_payload() {
  cd "${OPENWRT_DIR}"

  mkdir -p package/custom
  rm -rf package/custom/cb-riskcontrol package/custom/luci-theme-cbshield
  cp -a "${REPO_DIR}/packages/cb-riskcontrol" package/custom/cb-riskcontrol
  cp -a "${REPO_DIR}/luci-theme-cbshield" package/custom/luci-theme-cbshield

  mkdir -p files/etc/uci-defaults files/www/cb-portal
  cp -f "${REPO_DIR}/files/etc/uci-defaults/90_v3_optimizations" files/etc/uci-defaults/90_v3_optimizations
  cp -f "${REPO_DIR}/files/www/cb-portal/portal_config.json" files/www/cb-portal/portal_config.json

  cp -f "${REPO_DIR}/.config" .config
  cat >> .config <<'EOF'

# Kwrt single-device override
# CONFIG_TARGET_MULTI_PROFILE is not set
# CONFIG_TARGET_ALL_PROFILES is not set
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_jcg_q30-pro=y
CONFIG_TARGET_ROOTFS_PARTSIZE=1004
EOF

  if [ -f "${REPO_DIR}/profiles/stable.config" ]; then
    printf '\n# Profile override: stable\n' >> .config
    cat "${REPO_DIR}/profiles/stable.config" >> .config
  fi

  make defconfig
}

build_firmware() {
  cd "${OPENWRT_DIR}"
  make download -j"$(nproc)"
  find dl -size -1024c -delete
  make -j"$(nproc)" || make -j1 V=s
}

collect_artifacts() {
  rm -rf "${OUT_DIR}"
  mkdir -p "${OUT_DIR}"
  find "${OPENWRT_DIR}/bin/targets" -type f \( -name "*jcg_q30-pro*factory.bin" -o -name "*jcg_q30-pro*sysupgrade.bin" -o -name "*jcg_q30-pro*.manifest" \) -exec cp -f {} "${OUT_DIR}/" \;

  cd "${OUT_DIR}"
  sha256sum *.bin > SHA256SUMS
  ls -lh
}

install_build_deps

cd "${REPO_DIR}"
bash scripts/ci-smoke.sh "${REPO_DIR}"

rm -rf "${OPENWRT_DIR}"
git clone --depth 1 "${REPO_URL}" -b "${REPO_BRANCH}" "${OPENWRT_DIR}"

prepare_kwrt_tree
inject_cbshield_payload

if [ "${MODE}" = "prepare" ]; then
  echo "mode=prepare"
  echo "openwrt_dir=${OPENWRT_DIR}"
  echo "log=${LOG_FILE}"
  exit 0
fi

build_firmware
collect_artifacts

echo "mode=build"
echo "artifacts=${OUT_DIR}"
echo "log=${LOG_FILE}"
