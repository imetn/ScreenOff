# Screen Off — Agent 工作约定

> Screen Off 是一款让 Mac 保持在线，同时自动降低内建屏幕与键盘背光的轻量菜单栏工具。本文件只放高频约束；低频设计与实施细节放在 `docs/`。

## 技术栈与产品边界

- Swift 6、SwiftUI、AppKit、IOKit；项目由 XcodeGen 生成，最低支持 macOS 14。
- 首版只支持 Apple Silicon MacBook 的内建屏幕与内建键盘。
- 采用菜单栏常驻形态，无 Dock 图标；设置使用独立 `Settings` Scene。
- 首版采用 Developer ID 签名、公证后直接分发，不以 Mac App Store 为目标。
- 不确定或未验证的系统能力不得伪装成已完成；必须在文档和界面中明确状态。

## 仓库结构

| 目录 | 职责 |
|---|---|
| `ScreenOff/` | macOS App 源码 |
| `docs/` | 需求、架构、方案、待办与开发说明 |
| `script/` | 项目级构建、运行与验证脚本 |
| `.codex/` | Codex 本地运行入口 |

## 编码规约

- 如无必要，勿增实体；不引入 GPUI、Tauri、Electron 或跨平台抽象。
- 中文回复，言简意赅，按需使用 emoji。
- App 级状态集中管理；用户偏好使用 `UserDefaults`，系统能力放在独立 Service 中。
- 任何亮度、电源或合盖状态修改，都必须先保存原状态，并在关闭功能、退出、异常恢复时还原。
- 私有框架必须动态解析、能力探测、失败可降级；不得让缺失符号导致 App 崩溃。
- 合盖保持唤醒使用独立的 `PreventSystemSleep` 断言，必须与普通空闲断言分开持有、分开释放，断电时立即回退。
- 不保存输入内容、屏幕内容、远程会话信息或任何凭据。
- UI 重写、重排、新入口或视觉结构变化：写代码前先用 3–4 个 bullet 描述结构，等待确认。
- 影响架构、功能、分发、权限或安全边界的代码改动，必须同步更新 `docs/`。
- 减少无必要的 Xcode Build；完成一个可验证阶段后再构建。

## 工作流

- 大改动（超过 5 个文件或跨多个系统边界）开始前，先列出 3 条不变量并等待确认。
- 使用 `./script/build_and_run.sh` 作为统一运行入口。
- 系统能力必须在真实 MacBook 上验证；仅编译通过不能视为功能完成。
- 合盖、电源和亮度测试不得遗留系统状态；验证结束后检查并恢复默认状态。

## 文档、TODO 与方案

- `docs/todos/README.md` 是待办唯一入口。
- 短任务放 `docs/todos/`；详细实现和验收步骤放 `docs/plans/`。
- 完成后分别归档到 `docs/todos/finished/` 与 `docs/plans/finished/`。

## Git

提交信息格式：`<emoji> <type>(optional-scope): <中文简短描述>`

只使用：✨ feat、🐛 fix、📝 docs、♻️ refactor、🎨 style、⚡ perf、🌐 i18n、🔧 chore、🔧 ci、✅ test、⬆️ deps、🔖 release、🚧 wip。

