#!/usr/bin/env python3
"""校验 openwrt.ai 生成的 sysupgrade 镜像是否包含 CB-Shield 关键文件。"""

from __future__ import annotations

import argparse
import io
import sys
import tarfile
import tempfile
from pathlib import Path

try:
    from PySquashfsImage import SquashFsImage
except ModuleNotFoundError:
    print("缺少依赖: PySquashfsImage", file=sys.stderr)
    print("请先执行: python -m pip install PySquashfsImage", file=sys.stderr)
    sys.exit(2)


REQUIRED_PATHS = [
    "/usr/lib/lua/luci/controller/cbshield/index.lua",
    "/usr/lib/lua/luci/controller/cbshield/api.lua",
    "/usr/lib/lua/luci/view/cbshield/dashboard.htm",
    "/www/luci-static/cbshield/js/dashboard.js",
    "/www/cb-portal/index.html",
    "/etc/init.d/cb-riskcontrol",
    "/usr/bin/cb-riskcontrol",
]

DEFAULTS_CANDIDATES = [
    "/etc/uci-defaults/90_v3_optimizations",
    "/etc/uci-defaults/zz-asu-defaults",
]

HOMEPAGE_MARKER = "admin/cbshield/dashboard"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="校验 sysupgrade 镜像是否包含 CB-Shield UI、脚本和首启入口。"
    )
    parser.add_argument("image", help="sysupgrade 镜像路径")
    return parser.parse_args()


def select_required_member(archive: tarfile.TarFile, suffix: str) -> tarfile.TarInfo:
    for member in archive.getmembers():
        if member.name.endswith(suffix):
            return member
    raise FileNotFoundError(f"镜像中缺少 {suffix}")


def extract_rootfs(archive: tarfile.TarFile) -> bytes:
    root_member = select_required_member(archive, "/root")
    handle = archive.extractfile(root_member)
    if handle is None:
        raise RuntimeError("无法读取 rootfs 数据")
    return handle.read()


def read_file(image: SquashFsImage, path: str) -> bytes | None:
    try:
        node = image.select(path)
    except Exception:
        return None

    if node is None or not hasattr(node, "inode"):
        return None

    return image.read_file(node.inode)


def main() -> int:
    args = parse_args()
    image_path = Path(args.image).resolve()

    if not image_path.is_file():
        print(f"镜像不存在: {image_path}", file=sys.stderr)
        return 1

    with tarfile.open(image_path, "r:*") as archive:
        members = {member.name for member in archive.getmembers()}
        expected_suffixes = ["/CONTROL", "/kernel", "/root"]
        for suffix in expected_suffixes:
            select_required_member(archive, suffix)

        rootfs_bytes = extract_rootfs(archive)

    with tempfile.TemporaryDirectory(prefix="cbshield-rootfs-") as temp_dir:
        temp_root = Path(temp_dir) / "root.squashfs"
        temp_root.write_bytes(rootfs_bytes)

        with SquashFsImage.from_file(str(temp_root)) as squashfs:
            missing = [path for path in REQUIRED_PATHS if read_file(squashfs, path) is None]

            defaults_hits = {}
            homepage_configured = False
            for path in DEFAULTS_CANDIDATES:
                data = read_file(squashfs, path)
                if data is None:
                    continue
                text = data.decode("utf-8", "ignore")
                defaults_hits[path] = text
                if HOMEPAGE_MARKER in text:
                    homepage_configured = True

    print(f"镜像: {image_path}")
    print("tar 成员:")
    for suffix in ("/CONTROL", "/kernel", "/root"):
        match = next(name for name in members if name.endswith(suffix))
        print(f"  - {match}")

    if missing:
        print("缺失文件:")
        for path in missing:
            print(f"  - {path}")
        return 1

    print("关键文件检查: 通过")
    for path in REQUIRED_PATHS:
        print(f"  - {path}")

    if defaults_hits:
        print("首启脚本:")
        for path in defaults_hits:
            print(f"  - {path}")
    else:
        print("首启脚本: 未发现 90_v3_optimizations 或 zz-asu-defaults")

    print(f"默认首页: {'已配置' if homepage_configured else '未配置'} ({HOMEPAGE_MARKER})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
