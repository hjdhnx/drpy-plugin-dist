# drpy-plugin-dist

drpy-node (drpyS) 插件市场官方分发仓库：内置二进制插件（req-proxy / pvideo / pup-sniffer / mediaProxy）的打包发行。

## 使用方式

在 drpy-node 后台管理「插件管理 → 插件市场 → 市场源」中添加本仓库的市场源：

```
https://raw.githubusercontent.com/hjdhnx/drpy-plugin-dist/main/market.json
```

保存后即可在市场页浏览并一键安装。GitHub 访问不畅时，可在同一面板配置「GitHub 加速代理」（如 `https://github.catvod.com/`），安装器会自动兜底重试。

## 插件包规范

每个 zip 为 drpy-node 插件市场规范包（形态 A）：根级含 `plugin.json`（name/version/runtime/binaries 等 manifest）+ 各平台二进制文件。安装器会剥壳落位到 `plugins/<name>/`、校验 sha256、补齐执行权限并登记进 `.plugins.js`。

| 插件 | 说明 | 默认参数 | 平台 |
|---|---|---|---|
| req-proxy | 请求代理服务 | `-p 57571` | win / linux / android |
| pvideo | 嗷呜视频适配代理 | `-port 57572 -dns 8.8.8.8` | win / linux / android |
| pup-sniffer | drplayer 嗅探服务 | `-port 57573` | win / linux |
| mediaProxy | Go 媒体代理服务 | `-port 57574` | win / linux / android |

版本发布：更新 `dist/` 下插件包与 `market.json` 的 version/download/sha256 后打 tag 发 release。
