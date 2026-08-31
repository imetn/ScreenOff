# Screen Off

关闭屏幕，保持 Mac 在线。

Screen Off 是一款面向 Apple Silicon MacBook 的轻量 macOS 菜单栏工具。它计划提供普通保持唤醒、合盖后保持运行、自动降低内建屏幕亮度以及同步关闭键盘背光等能力。

## 当前状态

项目已完成基础初始化：

- SwiftUI `MenuBarExtra` 菜单栏窗口
- 独立设置窗口
- 可持久化的首版偏好模型
- XcodeGen 工程配置
- Codex Run 入口与项目级构建脚本
- MVP 需求、架构和实施方案

当前界面仅保存配置，尚未接入电源、屏幕、键盘与合盖系统控制。

## 开发

环境要求：

- Xcode 26.6 或兼容版本
- XcodeGen
- macOS 14+

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

文档入口见 [docs/README.md](docs/README.md)。

