#!/usr/bin/env python3
"""从 openwrt.ai 配置模板渲染构建参数。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="渲染 openwrt.ai 请求模板")
    parser.add_argument(
        "--profile",
        default="profiles/openwrtai-jcg-q30-pro.json",
        help="配置模板路径",
    )
    parser.add_argument(
        "--format",
        choices=("json", "summary", "checklist"),
        default="summary",
        help="输出格式",
    )
    parser.add_argument(
        "--overlay",
        help="覆盖 files_path，对应 openwrt.ai 已上传文件名，例如 liujinbf/cbshield-openwrtai-overlay.tgz",
    )
    parser.add_argument(
        "--defaults-inline",
        action="store_true",
        help="把 defaults_file 的内容内联到 JSON 请求里",
    )
    return parser.parse_args()


def load_profile(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_defaults_text(repo_root: Path, profile: dict, inline: bool) -> str:
    if not inline:
        return ""

    defaults_file = repo_root / profile["defaults_file"]
    if not defaults_file.is_file():
        raise FileNotFoundError(f"defaults 文件不存在: {defaults_file}")
    return defaults_file.read_text(encoding="utf-8")


def build_request(profile: dict, defaults_text: str, overlay: str | None) -> dict:
    payload = {
        "target": profile["target"],
        "profile": profile["profile"],
        "packages": profile["packages"],
        "defaults": defaults_text,
        "version": "",
        "diff_packages": False,
        "rootfs_size_mb": profile["rootfs_size_mb"],
        "filesystem": profile["filesystem"],
        "rootfs": False,
        "vmdk": False,
        "efi": profile["efi"],
        "files_path": overlay or "",
        "more": "",
    }
    return payload


def render_summary(profile: dict, payload: dict) -> str:
    lines = [
        f"模板: {profile['name']}",
        f"机型: {profile['target']} / {profile['profile']}",
        f"主题: {profile['theme']}",
        f"Web 服务器: {profile['webserver']}",
        "基础包:",
    ]
    for package in profile["packages"]:
        lines.append(f"  - {package}")

    lines.append(f"overlay 文件: {profile['overlay_file']}")
    lines.append(f"defaults 文件: {profile['defaults_file']}")
    lines.append(f"API files_path: {payload['files_path'] or '(需上传后填写)'}")
    lines.append("网站字段建议:")
    for key, value in profile["form_defaults"].items():
        lines.append(f"  - {key} = {value}")

    lines.append("可选代理项:")
    for item in profile["site_optional_features"]:
        lines.append(f"  - {item['field']} = {item['enabled']} ({item['notes']})")

    lines.append("备注:")
    for note in profile["notes"]:
        lines.append(f"  - {note}")
    return "\n".join(lines)


def render_checklist(profile: dict, payload: dict) -> str:
    lines = [
        f"构建模板: {profile['name']}",
        "",
        "构建前:",
        f"1. 执行 `powershell -ExecutionPolicy Bypass -File .\\scripts\\openwrtai.ps1 prepare`",
        f"2. 确认覆盖包存在: `{profile['overlay_file']}`",
        f"3. 确认 defaults 存在: `{profile['defaults_file']}`",
        "",
        "网站填写:",
        f"1. 机型选择 `JCG Q30 PRO`",
        f"2. 主题选择 `{profile['theme']}`",
        f"3. Web 服务器选择 `{profile['webserver']}`",
        f"4. 文件系统选择 `{profile['filesystem']}`",
        f"5. 上传自定义文件包 `{profile['overlay_file']}`",
        f"6. 粘贴 `{profile['defaults_file']}` 内容到 defaults 文本框",
        "7. 按下面字段检查网站表单:",
    ]

    for key, value in profile["form_defaults"].items():
        lines.append(f"   - {key} = {value}")

    lines.extend(
        [
            "",
            "建议基础包:",
        ]
    )
    for package in profile["packages"]:
        lines.append(f"  - {package}")

    lines.extend(
        [
            "",
            "API 请求关键字段:",
            f"  - target = {payload['target']}",
            f"  - profile = {payload['profile']}",
            f"  - files_path = {payload['files_path'] or '(上传完成后由网站返回用户名/文件名)'}",
            f"  - rootfs_size_mb = {payload['rootfs_size_mb']}",
            "",
            "构建后验收:",
            "1. 下载 sysupgrade 固件到 `.work/`",
            "2. 执行 `powershell -ExecutionPolicy Bypass -File .\\scripts\\openwrtai.ps1 verify -ImagePath .\\.work\\你的固件.bin`",
            "3. 确认输出里有 `关键文件检查: 通过`",
            "4. 确认输出里有 `默认首页: 已配置 (admin/cbshield/dashboard)`",
            "",
            "备注:",
        ]
    )
    for note in profile["notes"]:
        lines.append(f"  - {note}")

    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    profile_path = (repo_root / args.profile).resolve()
    profile = load_profile(profile_path)
    defaults_text = load_defaults_text(repo_root, profile, args.defaults_inline)
    payload = build_request(profile, defaults_text, args.overlay)

    if args.format == "json":
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif args.format == "checklist":
        print(render_checklist(profile, payload))
    else:
        print(render_summary(profile, payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
