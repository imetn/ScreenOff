# Screen Off

简体中文 · [English](README.en.md)

关闭屏幕，保持 Mac 在线。

Screen Off 是一款面向 Apple Silicon MacBook 的轻量 macOS 菜单栏工具。
当 MacBook 作为远程控制主机长期在线时，它让机器保持唤醒，
同时在没有物理输入时把内建屏幕和键盘背光降到最低。

## 下载安装

前往 [Releases](https://github.com/imetn/ScreenOff/releases/latest) 下载 `ScreenOff.dmg`，
打开后把 Screen Off 拖入「应用程序」即可。安装包由 Developer ID 签名并经 Apple 公证，
之后的版本可在 App 内通过 Sparkle 直接检查、下载并安装。

系统要求：macOS 14 及以上，Apple Silicon MacBook（内建屏幕与内建键盘）。

## 功能

- **保持电脑唤醒**：阻止空闲睡眠，可在 `pmset -g assertions` 中观察。
- **合盖后保持唤醒**：使用独立断言，系统限定仅在接通电源时生效，断电自动回退。
- **自动关闭屏幕**：空闲 1 分钟至 4 小时后保存原亮度并降至最低，物理输入即刻还原。
- **同时关闭键盘背光**：手动或自动关屏时跟随关闭，并与屏幕一同恢复原值。
- **立即关闭屏幕**与**亮度滑杆**：菜单栏窗口内直接操作。
- **登录时启动**：通过 `SMAppService` 注册，无额外 Helper。
- **应用内更新**：集成 Sparkle 2，使用签名 Feed 与 EdDSA 验签。
- **原生设置窗口**：按“功能 / 通用 / 关于”分栏；打开时显示 Dock 图标，关闭后恢复为纯菜单栏 App。

空闲判定只认物理键盘与触控板输入（`IOHIDManager`），
软件注入的事件不会重置计时，因此远程操作不会点亮本地屏幕。

## 权限

「自动关闭屏幕」需要系统的「输入监控」权限，用于订阅内建键盘与触控板的 HID 事件；
回调只更新一个时间戳，不读取按键或坐标。首次打开该开关时会弹出系统授权，
授权后无需重启。未授权时功能降级为系统事件源读数，并在界面上明示无法区分远程输入，
同时提供跳转系统设置的入口。

## 当前状态

已在真机验证：断言创建与释放、亮度与背光的读写还原、自动关屏、正常退出还原、
异常终止后重启还原、v0.1.0 → v0.1.1 的签名更新链路。
详见[真机验证记录](docs/reference/verification-2026-09-01.md)。

尚待验证：物理合盖行为、拔电源回退、真实远程会话、签名构建上的登录启动与输入监控授权流。
在这些验证完成前，「合盖后保持唤醒」应视为实验性功能。

## 开发

环境要求：Xcode 26.6、XcodeGen、macOS 14+。

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

单元测试只覆盖档位与偏好持久化等纯逻辑，不启动 App，也不依赖真机能力：

```bash
xcodebuild -project ScreenOff.xcodeproj -scheme ScreenOff -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions 在每次 push 与 Pull Request 上执行编译与单元测试。
屏幕、键盘、电源与合盖能力仍必须在真实 MacBook 上验证，编译通过不代表功能完成。

App 主图标为 Icon Composer 文档 `ScreenOff/Resources/AppIcon.icon`，
用 Icon Composer 打开编辑；菜单栏三态字形为 `Assets.xcassets` 中的模板 SVG。

文档入口见 [docs/README.md](docs/README.md)。

## 许可

以 [MIT 许可](LICENSE) 发布。
