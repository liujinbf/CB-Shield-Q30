#!/usr/bin/env python3
"""openwrt.ai 半自动构建脚本。"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import time
import uuid
from pathlib import Path

import requests


AJAX_URL = "https://openwrt.ai/wp-admin/admin-ajax.php"
BUILD_URL = "https://openwrt.ai/api/v1/build"
REFERER_URL = "https://openwrt.ai/?target=mediatek%2Ffilogic&id=jcg_q30-pro"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="上传 overlay 并触发 openwrt.ai 构建")
    parser.add_argument(
        "--profile",
        default="profiles/openwrtai-jcg-q30-pro.json",
        help="配置模板路径",
    )
    parser.add_argument(
        "--cookie-header",
        help="浏览器请求里的完整 Cookie 头",
    )
    parser.add_argument(
        "--cookie-file",
        help="包含完整 Cookie 头的文本文件路径",
    )
    parser.add_argument(
        "--upload-nonce",
        help="文件上传 nonce；如果已经上传过 overlay，可改用 --overlay-remote",
    )
    parser.add_argument(
        "--overlay-file",
        help="本地 overlay 路径，默认取配置模板里的 overlay_file",
    )
    parser.add_argument(
        "--overlay-remote",
        help="远端 files_path，例如 liujinbf/cbshield-openwrtai-overlay.tgz",
    )
    parser.add_argument(
        "--defaults-inline",
        action="store_true",
        help="把 defaults_file 内容直接注入构建请求",
    )
    parser.add_argument(
        "--download-dir",
        default=".work",
        help="下载产物目录",
    )
    parser.add_argument(
        "--download-image",
        choices=("sysupgrade", "factory", "none"),
        default="sysupgrade",
        help="构建成功后下载哪类镜像",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=5,
        help="轮询间隔秒数",
    )
    parser.add_argument(
        "--max-rounds",
        type=int,
        default=120,
        help="最大轮询次数",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="下载后调用 verify-openwrtai-image.py 校验",
    )
    return parser.parse_args()


def load_profile(repo_root: Path, profile_path: str) -> dict:
    path = (repo_root / profile_path).resolve()
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_cookie_header(args: argparse.Namespace, repo_root: Path) -> str:
    if args.cookie_header:
        return args.cookie_header.strip()
    if args.cookie_file:
        cookie_path = (repo_root / args.cookie_file).resolve()
        return cookie_path.read_text(encoding="utf-8").strip()
    raise SystemExit("必须提供 --cookie-header 或 --cookie-file")


def load_defaults_text(repo_root: Path, profile: dict, inline: bool) -> str:
    if not inline:
        return ""

    defaults_path = repo_root / profile["defaults_file"]
    return defaults_path.read_text(encoding="utf-8")


def build_payload(profile: dict, defaults_text: str, files_path: str) -> dict:
    return {
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
        "files_path": files_path,
        "more": "",
    }


def generate_verification_header() -> str:
    raw = json.dumps({"uuid": str(uuid.uuid4())}, separators=(",", ":"))
    xored = "".join(chr(ord(ch) ^ 0x50) for ch in raw)
    return base64.b64encode(xored.encode("utf-8")).decode("ascii")


def build_common_headers(cookie_header: str, content_type: str | None = None) -> dict:
    headers = {
        "Cookie": cookie_header,
        "Referer": REFERER_URL,
        "Origin": "https://openwrt.ai",
        "User-Agent": "Mozilla/5.0",
    }
    if content_type:
        headers["Content-Type"] = content_type
    return headers


def upload_overlay(cookie_header: str, upload_nonce: str, overlay_file: Path) -> str:
    headers = build_common_headers(cookie_header)
    with overlay_file.open("rb") as handle:
        response = requests.post(
            AJAX_URL,
            headers=headers,
            data={"action": "upload_file", "security": upload_nonce},
            files={"file": (overlay_file.name, handle, "application/gzip")},
            timeout=180,
        )
    response.raise_for_status()
    data = response.json()
    if not data.get("success"):
        raise RuntimeError(f"上传失败: {data}")
    return data["data"]["filename"]


def submit_build(cookie_header: str, payload: dict) -> requests.Response:
    headers = build_common_headers(cookie_header, "application/json")
    headers["Ng-One-Time-Verif-Value"] = generate_verification_header()
    return requests.post(BUILD_URL, headers=headers, json=payload, timeout=180)


def pick_image(result: dict, image_type: str) -> dict | None:
    if image_type == "none":
        return None
    for image in result.get("images", []):
        if image.get("type") == image_type:
            return image
    return None


def download_image(result: dict, image: dict, download_dir: Path) -> Path:
    request_hash = result["request_hash"]
    url = f"https://dl.openwrt.ai/store/{request_hash}/{image['name']}"
    download_dir.mkdir(parents=True, exist_ok=True)
    output_path = download_dir / image["name"]

    with requests.get(url, stream=True, timeout=300) as response:
        response.raise_for_status()
        with output_path.open("wb") as handle:
            for chunk in response.iter_content(1024 * 1024):
                if chunk:
                    handle.write(chunk)
    return output_path


def run_verify(repo_root: Path, image_path: Path) -> None:
    verify_script = repo_root / "scripts" / "verify-openwrtai-image.py"
    subprocess.run(
        ["python", str(verify_script), str(image_path)],
        check=True,
        cwd=str(repo_root),
    )


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    profile = load_profile(repo_root, args.profile)
    cookie_header = resolve_cookie_header(args, repo_root)
    defaults_text = load_defaults_text(repo_root, profile, args.defaults_inline)

    if args.overlay_remote:
        files_path = args.overlay_remote
        print(f"复用远端 overlay: {files_path}")
    else:
        if not args.upload_nonce:
            raise SystemExit("未提供 --upload-nonce，且没有指定 --overlay-remote")
        overlay_path = Path(args.overlay_file or (repo_root / profile["overlay_file"])).resolve()
        if not overlay_path.is_file():
            raise SystemExit(f"overlay 文件不存在: {overlay_path}")
        uploaded_name = upload_overlay(cookie_header, args.upload_nonce, overlay_path)
        files_path = uploaded_name
        print(f"上传成功: {uploaded_name}")

    payload = build_payload(profile, defaults_text, files_path)
    print("开始构建...")

    result = None
    for round_index in range(1, args.max_rounds + 1):
        response = submit_build(cookie_header, payload)
        body = response.json()
        status = response.status_code
        detail = body.get("detail", "")
        print(f"[round {round_index}] status={status} detail={detail}")

        if status == 200:
            result = body
            break

        if status == 202:
            time.sleep(args.poll_interval)
            continue

        if status == 400 and "登录" in detail:
            raise SystemExit("构建失败: 登录态失效，请刷新页面并重新导出 Cookie")

        raise SystemExit(f"构建失败: HTTP {status} {json.dumps(body, ensure_ascii=False)}")

    if result is None:
        raise SystemExit("构建超时，未拿到成功结果")

    print(f"构建成功: request_hash={result['request_hash']}")
    for image in result.get("images", []):
        print(f"  - {image['type']}: {image['name']}")

    selected = pick_image(result, args.download_image)
    if selected is None:
        if args.download_image != "none":
            print(f"未找到 {args.download_image} 镜像，跳过下载")
        return 0

    downloaded = download_image(result, selected, (repo_root / args.download_dir).resolve())
    print(f"已下载: {downloaded}")

    if args.verify:
        run_verify(repo_root, downloaded)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
