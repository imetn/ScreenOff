# Screen Off

关闭屏幕，保持 Mac 在线。

Screen Off 是一款面向 Apple Silicon MacBook 的轻量 macOS 菜单栏工具。
当 MacBook 作为远程控制主机长期在线时，它让机器保持唤醒，
同时在没有物理输入时把内建屏幕和键盘背光降到最低。

## 功能

- **保持电脑唤醒**：阻止空闲睡眠，可在 `pmset -g assertions` 中观察。
- **合盖后保持唤醒**：使用独立断言，系统限定仅在接通电源时生效，断电自动回退。
- **自动关闭屏幕**：空闲 10 秒至 4 小时后保存原亮度并降至最低，物理输入即刻还原。
- **同时关闭键盘背光**：手动或自动关屏时跟随关闭，并与屏幕一同恢复原值。
- **立即关闭屏幕**与**亮度滑杆**：菜单栏窗口内直接操作。
- **登录时启动**：通过 `SMAppService` 注册，无额外 Helper。
- **应用内更新**：集成 Sparkle 2；GitHub 更新源发布后可直接检查、下载并安装新版本。
- **原生设置窗口**：按“功能 / 通用 / 关于”分栏；打开时显示 Dock 图标，关闭后恢复为纯菜单栏 App。

空闲判定只认物理键盘与触控板输入（`IOHIDManager`），
软件注入的事件不会重置计时，因此远程操作不会点亮本地屏幕。

## 当前状态

核心链路已在真机跑通：断言创建与释放、亮度与背光的读写还原、
自动关屏、正常退出还原、异常终止后重启还原、菜单栏图标三态。
详见[真机验证记录](docs/reference/verification-2026-09-01.md)。

尚待验证：物理合盖行为、拔电源回退、真实 UU 远程会话、签名构建上的登录启动。
GitHub 仓库与 Sparkle 签名更新源已配置；正式更新在首个 Developer ID 签名、公证版本发布后开放。
直接下载安装使用定制 DMG，打开后将 Screen Off 拖入“应用程序”即可。

## 开发

环境要求：Xcode 26.6 或兼容版本、XcodeGen、macOS 14+。

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

重新生成 App 图标（几何取自 Figma 定稿）：

```bash
xcrun swift script/make_app_icon.swift
```

文档入口见 [docs/README.md](docs/README.md)。
