# 应用内更新与发布

Screen Off 使用 Sparkle 2 更新 Developer ID 直接分发的普通 App bundle。
更新包与 Appcast 由 GitHub Releases 托管，Feed 使用固定地址：

`https://github.com/imetn/ScreenOff/releases/latest/download/appcast.xml`

App 同时启用 `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction`，
先验证签名 Feed，再验证归档的 Sparkle EdDSA 签名。

## 发布前一次性配置

1. 在 Xcode 27 登录公司开发者账号，使用公司团队 `PRYY9PKKUP`。
2. 由 Xcode Direct Distribution 创建或下载公司 `Developer ID Application` 证书。
3. Sparkle `generate_keys` 生成的私钥保存在登录钥匙串；仓库只保存公钥。
4. GitHub CLI 登录拥有 `imetn/ScreenOff` 发布权限的账号。

不得使用个人 Team、`Apple Development`、`Apple Distribution` 或临时签名包发布更新。

## 每次发布

1. 递增 `project.yml` 中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
2. 新增对应的 `docs/releases/v<version>.md`，提交后保持工作区干净。
3. 运行 `./script/release.sh build` 生成并验证本地产物。
4. 运行 `./script/release.sh --publish` 推送 `main` 并创建 GitHub Release。
5. 从上一正式版本执行一次真实的“检查更新”与安装复验。

发布脚本会依次执行：Xcode Archive、公司 Developer ID 自动签名、上传 Apple 公证、
导出带 Ticket 的 App、Gatekeeper 验证、ZIP 打包、签名 Appcast 生成与 GitHub Release 发布。

## 安全边界

- Developer ID 与 Apple 公证证明应用来源；Sparkle EdDSA 证明更新归档来自发布者。
- Appcast 本身也必须通过同一 Sparkle 密钥签名，且所有 URL 必须使用 HTTPS。
- 不启用系统信息采集，不向 Appcast 附加设备画像。
- Screen Off 当前不启用 App Sandbox，因此不启用 Sparkle 的沙盒 XPC 配置。
- 导出后必须校验 `TeamIdentifier=PRYY9PKKUP`，否则发布脚本立即失败。
