#!/usr/bin/env python3
"""输出 CB-Shield 固件刷机后的实机验收清单。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="渲染刷机后验收清单")
    parser.add_argument(
        "--profile",
        default="profiles/openwrtai-jcg-q30-pro.json",
        help="配置模板路径",
    )
    return parser.parse_args()


def load_profile(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    profile = load_profile((repo_root / args.profile).resolve())

    lines = [
        f"刷机后验收模板: {profile['name']}",
        "",
        "基础连通:",
        "1. 路由器上电完成后，确认 LAN 口能获取到地址。",
        "2. 打开管理地址，确认 LuCI 可访问。",
        "3. 确认首页进入 `admin/cbshield/dashboard`，而不是默认状态页。",
        "",
        "CB-Shield UI:",
        "1. 检查仪表盘是否能看到 CPU、内存、在线终端和风险状态卡片。",
        "2. 检查 `风险控制` 页面是否能正常加载，不出现空白页或 JS 报错。",
        "3. 检查 `网络状态` 页面是否能看到 LAN/WAN/WiFi 信息。",
        "4. 检查 `运维中心` 和 `时间线` 页面是否能打开。",
        "",
        "接口与静态资源:",
        "1. 浏览器打开开发者工具，确认 `dashboard.js`、`theme.js` 返回 200。",
        "2. 轮询接口至少检查这些路径返回 200:",
        "   - /cgi-bin/luci/admin/cbshield/api/sysinfo",
        "   - /cgi-bin/luci/admin/cbshield/api/riskstatus",
        "   - /cgi-bin/luci/admin/cbshield/api/network",
        "   - /cgi-bin/luci/admin/cbshield/api/connections",
        "",
        "服务状态:",
        "1. 确认以下服务已启用并能启动:",
        "   - cb-riskcontrol",
        "   - cb-portal",
        "   - cb-healthcheck",
        "   - cb-ha-monitor",
        "   - cb-dns-guard",
        "2. 如已选择代理栈，再确认主代理服务可正常启动。",
        "",
        "Portal:",
        "1. 访问 `http://路由器IP:8080/`，确认 Portal 页面可打开。",
        "2. 检查 Portal 页面中的本地配置是否已加载。",
        "",
        "网络与 WiFi:",
        "1. 确认 LAN 地址符合你的网站构建配置。",
        "2. 确认 `office_24g` 和 `office_5g` 已创建并桥接到 `lan`。",
        "3. 确认 WiFi 能正常连接并获取 LAN 网段地址。",
        "",
        "验收命令:",
        "1. 在本地执行固件镜像校验:",
        "   powershell -ExecutionPolicy Bypass -File .\\scripts\\openwrtai.ps1 verify -ImagePath .\\.work\\你的固件.bin",
        "2. 在路由器侧可选执行:",
        "   /etc/init.d/cb-riskcontrol status",
        "   /etc/init.d/cb-healthcheck status",
        "   logread | grep cb-",
        "",
        "结论判定:",
        "1. 如果 LuCI 首页、CB 页面、API、Portal、服务都正常，则这版固件可进入实测阶段。",
        "2. 如果 UI 文件在镜像里但首页未切换，优先检查 defaults 是否注入成功。",
        "3. 如果页面能打开但数据卡片为空，优先检查 `cbshield/api/*` 路由和服务状态。",
    ]

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
