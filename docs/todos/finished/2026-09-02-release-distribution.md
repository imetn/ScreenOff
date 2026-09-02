# 已完成 · 2026-09-02 发布与更新

- 使用公司 `Developer ID Application` 完成 App 与 DMG 签名、Apple 公证、Ticket 装订和 Gatekeeper 验证。
- 发布 [v0.1.0](https://github.com/imetn/ScreenOff/releases/tag/v0.1.0) 与 [v0.1.1](https://github.com/imetn/ScreenOff/releases/tag/v0.1.1)，提供 DMG、ZIP、签名 Appcast 与 SHA-256 校验文件。
- 从 `/Applications` 中运行的 0.1.0 通过 Sparkle 更新到 0.1.1，并完成下载、验签、替换和自动重启。
- 更新后的 App 与发布包代码签名哈希一致，仍由公司团队签名并被 Gatekeeper 识别为已公证 Developer ID 软件。
- 定制 DMG 使用语言无关的 App → Applications 拖拽布局，并完成实际挂载与窗口复核。

详见 [应用内更新与发布](../../deployment/updates.md)。
