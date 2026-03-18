# 2026-03-18 Passwall 构建发布说明

这是一版通过 `openwrt.ai` 远程半自动流程实际构建、下载并完成镜像校验的固件记录，适合作为实机刷机测试基线。

## 构建信息

- 构建日期：`2026-03-18`
- 目标平台：`mediatek/filogic`
- 设备：`jcg_q30-pro`
- 方案模板：[openwrtai-jcg-q30-pro-passwall.json](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/profiles/openwrtai-jcg-q30-pro-passwall.json)
- 请求哈希：`ab5c6a29c8732aa5c9e5313ffa0829ce`
- 远端 overlay：`liujinbf/cbshield-openwrtai-overlay.tgz`
- defaults：构建时使用仓库当前生成的 `defaults` 内容内联提交

## 下载链接

- Sysupgrade: [kwrt-03.18.2026-mediatek-filogic-jcg_q30-pro-squashfs-sysupgrade.bin](https://dl.openwrt.ai/store/ab5c6a29c8732aa5c9e5313ffa0829ce/kwrt-03.18.2026-mediatek-filogic-jcg_q30-pro-squashfs-sysupgrade.bin)
- Factory: [kwrt-03.18.2026-mediatek-filogic-jcg_q30-pro-squashfs-factory.bin](https://dl.openwrt.ai/store/ab5c6a29c8732aa5c9e5313ffa0829ce/kwrt-03.18.2026-mediatek-filogic-jcg_q30-pro-squashfs-factory.bin)

本地已下载文件：

- [kwrt-03.18.2026-mediatek-filogic-jcg_q30-pro-squashfs-sysupgrade.bin](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/.work/kwrt-03.18.2026-mediatek-filogic-jcg_q30-pro-squashfs-sysupgrade.bin)

## 已验证结果

本地已通过 [verify-openwrtai-image.py](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/scripts/verify-openwrtai-image.py) 校验，关键结论如下：

- `cbshield` LuCI 控制器已进入镜像
- `cbshield` 仪表盘模板已进入镜像
- `cbshield` 静态资源已进入镜像
- `cb-riskcontrol` 脚本与 init 服务已进入镜像
- `cb-portal` 页面已进入镜像
- `zz-asu-defaults` 已进入镜像
- 默认首页已配置为 `admin/cbshield/dashboard`

## 建议刷机方式

- 已在 OpenWrt 上运行并保留配置：优先使用 `sysupgrade`
- 从原厂固件或恢复环境首次刷入：使用 `factory`

## 刷机后重点检查

参考完整清单：[postflash-acceptance.md](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/docs/postflash-acceptance.md)

最关键的 5 项：

1. LuCI 首页是否直接进入 `admin/cbshield/dashboard`
2. `风险控制`、`网络状态`、`运维中心` 页面是否都能打开
3. `/cgi-bin/luci/admin/cbshield/api/*` 是否返回 200
4. `cb-riskcontrol`、`cb-portal`、`cb-healthcheck`、`cb-ha-monitor`、`cb-dns-guard` 是否正常启动
5. `http://路由器IP:8080/` 的 Portal 是否可访问

## 注意事项

- 这版固件验证的是“镜像内容正确”和“默认首页已切换”，还没有替代真实设备刷机测试。
- 这次构建复用了站点上已有的远端 overlay。如果下次本地 overlay 有变更，建议先重新执行 `prepare` 并重新上传。
- 如果后续需要 OpenClash 版本，不要复用这份 Passwall 发布说明，改用 [openwrtai-jcg-q30-pro-openclash.json](/D:/下载/CB-Shield-Q30/CB-Shield-Q30/profiles/openwrtai-jcg-q30-pro-openclash.json) 重新构建。
