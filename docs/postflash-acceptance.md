# 刷机后验收

推荐在每次 `openwrt.ai` 构建后，按下面顺序做实机验收。

## 输出验收清单

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 acceptance
```

指定代理方案模板：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 acceptance -ProfilePath profiles/openwrtai-jcg-q30-pro-passwall.json
```

## 核心检查项

- LuCI 首页是否直接进入 `admin/cbshield/dashboard`
- `cbshield` 页面和静态资源是否正常加载
- `cbshield/api/*` 轮询接口是否返回 200
- `cb-riskcontrol`、`cb-portal`、`cb-healthcheck`、`cb-ha-monitor`、`cb-dns-guard` 是否正常启动
- `http://路由器IP:8080/` 的 Portal 是否可访问
- `office_24g` / `office_5g` 是否存在并桥接到 `lan`

## 固件侧与设备侧结合

先在本地校验镜像内容：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\openwrtai.ps1 verify -ImagePath .\.work\你的固件.bin
```

再做实机验收。两者都通过，才建议进入对外使用或批量刷机。
