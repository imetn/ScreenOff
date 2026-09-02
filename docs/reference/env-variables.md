# 环境变量

Screen Off 运行时不依赖环境变量；更新 Feed、公钥与 GitHub 地址编译进 App 的 `Info.plist`。

脚本支持以下可选覆盖：

- `DEVELOPER_DIR`：选择 Xcode 工具链；构建与发布脚本默认使用稳定版 Xcode 26.6，需要 beta SDK 时显式设置。
- `SCREENOFF_TEAM_ID`：Developer ID 团队，默认固定为公司团队 `PRYY9PKKUP`。
- `SCREENOFF_NOTARY_PROFILE`：`notarytool` 钥匙串配置名，默认为 `ScreenOff-Notary`。

Sparkle 私钥由官方工具保存在登录钥匙串，不通过环境变量传递，也不得写入仓库。
