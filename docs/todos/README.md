# Todos — 待办统一入口

> 本目录是全项目待办的唯一入口。短任务放这里；长方案、调研、迁移步骤放 `docs/plans/`。
> 每条 TODO 只写一句话：做什么 + 为何 + 相关 plan 链接（如有）。
> 完成后移到 `finished/` 并注明日期。

## 🔴 高优先

- 物理合盖 + 拔电源复验合盖保持唤醒的实际行为，确认断言生效且断电后回退；见 [真机验证记录](../reference/verification-2026-09-01.md)。若 Apple Silicon 无外显时合盖仍会睡眠，须把该功能限定为「接外显时有效」并同步 README 口径。
- 使用 UU 远程和真实本地输入完成端到端验收，确认远程操作不会点亮本地屏幕，也不会打断自动关屏。
- 在正式签名构建上复验「登录时启动」与「输入监控」授权闭环：首次开启自动关屏弹窗、授权后不重启即接回 HID、拒绝后「前往系统设置」入口可用；见 [授权闭环实现记录](finished/2026-09-02-input-monitoring-guidance.md)。
- 首次 CI 运行需确认 `macos-26` runner 可用且默认 Xcode 能编译 Icon Composer 图标；不可用则更换 runner 或显式 `xcode-select`。

## 🟡 中优先

- 决定 Bundle ID 是否长期保留 `com.ethan.screenoff`；如需改名，须在大范围宣传前完成，并为 Sparkle 更新、登录项与偏好做迁移。
- 为 README 补一张菜单栏窗口截图。
- 为 App 与 Sparkle 更新窗口补齐简体中文、英文的随系统语言本地化；DMG 继续使用无语言布局。

## 🟢 低优先

暂无。

## 归档

- [finished/](finished/) — 已完成任务归档
