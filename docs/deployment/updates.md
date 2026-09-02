# 应用内更新与发布

Screen Off 使用 Sparkle 2 更新 Developer ID 直接分发的普通 App bundle。
更新包与 Appcast 由 GitHub Releases 托管，Feed 使用固定地址：

`https://github.com/imetn/ScreenOff/releases/latest/download/appcast.xml`

App 同时启用 `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction`，
先验证签名 Feed，再验证归档的 Sparkle EdDSA 签名。

## 发布前一次性配置

1. 在 Xcode（26.6 或更高稳定版）登录公司开发者账号，使用公司团队 `PRYY9PKKUP`。
2. 由 Xcode Direct Distribution 创建或下载公司 `Developer ID Application` 证书。
3. Sparkle `generate_keys` 生成的私钥保存在登录钥匙串；仓库只保存公钥。
4. GitHub CLI 登录拥有 `imetn/ScreenOff` 发布权限的账号。
5. 使用 `notarytool store-credentials` 将公司公证凭据保存为钥匙串配置 `ScreenOff-Notary`。
6. 安装开源 DMG 构建工具：`brew install create-dmg`。

不得使用个人 Team、`Apple Development`、`Apple Distribution` 或临时签名包发布更新。

## 每次发布

1. 递增 `project.yml` 中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
2. 新增对应的 `docs/releases/v<version>.md`，提交后保持工作区干净。
3. 运行 `./script/release.sh build` 生成并验证本地产物。
4. 运行 `./script/release.sh --publish` 推送 `main` 并创建 GitHub Release。
5. 从上一正式版本执行一次真实的“检查更新”与安装复验。

发布脚本会依次执行：Xcode Archive、公司 Developer ID 自动签名、上传 Apple 公证、
导出带 Ticket 的 App、Gatekeeper 验证、ZIP 打包、签名 Appcast 生成、
定制拖拽安装 DMG、DMG 独立签名与公证、GitHub Release 发布。

Sparkle 的 Appcast 输入目录只放 ZIP 更新归档；DMG 是首次安装资产，不参与 Appcast 生成，
避免同一 bundle 版本被识别成两个重复更新。

DMG 使用 560 × 360 的 Finder 窗口，包含 Screen Off 与 Applications 两个图标、
拖拽方向提示和专属背景。背景只保留产品名与通用图形，不固定中文或英文说明；
背景源文件位于 `script/assets/dmg-background.svg`。

## 首次发布验收

2026-09-02 已完成 v0.1.0 → v0.1.1 的实际升级：旧版从 GitHub Feed 发现新版，
Sparkle 下载并替换 `/Applications/ScreenOff.app` 后自动重启。更新后版本为 0.1.1 (2)，
代码签名哈希与发布包一致，App 与 DMG 均通过 stapler 和 Gatekeeper 验证。

## 卸载

1. 在“通用”中关闭“登录时启动”，再退出 Screen Off。
2. 将 `/Applications/ScreenOff.app` 移到废纸篓。
3. 如需同时清除偏好，可执行 `defaults delete com.ethan.screenoff`；正常卸载无需此步骤。

## 安全边界

- Developer ID 与 Apple 公证证明应用来源；Sparkle EdDSA 证明更新归档来自发布者。
- Appcast 本身也必须通过同一 Sparkle 密钥签名，且所有 URL 必须使用 HTTPS。
- 不启用系统信息采集，不向 Appcast 附加设备画像。
- Screen Off 当前不启用 App Sandbox，因此不启用 Sparkle 的沙盒 XPC 配置。
- 导出后必须校验 `TeamIdentifier=PRYY9PKKUP`，否则发布脚本立即失败。
- DMG 也必须由同一公司 `Developer ID Application` 签名、单独公证并装订 Ticket。
