<h1 align="center"><img src="Docs/assets/readme/app-icon-final-1024.png" alt="Screen Off" width="52" align="center"> Screen Off</h1>

<p align="center"><a href="README.md">English</a> · 简体中文</p>

<p align="center"><strong>Mac 保持唤醒，屏幕无需常亮。</strong></p>

Screen Off 为 Vibe Coding 和远程控制场景准备。MacBook 空闲后，它会关闭内建屏幕和键盘背光，同时保持 Mac 在线。授权「输入监控」后，远程操作不会点亮本机屏幕；碰一下键盘或触控板，就会恢复原来的亮度。

<p align="center">
  <img src="Docs/assets/readme/menu-bar-light.png" alt="Screen Off 菜单栏浅色模式" width="46%">
  <img src="Docs/assets/readme/menu-bar-dark.png" alt="Screen Off 菜单栏深色模式" width="46%">
</p>

## 能做什么

- 关闭屏幕，也可以在空闲一段时间后自动关闭。
- 保持 Mac 唤醒，远程操作不会点亮本机屏幕。
- 检测到本机输入后，恢复原来的屏幕和键盘亮度。
- 关闭本机键盘与触控板，屏幕一并熄灭；按住 Fn + Delete 一秒解锁。
- 接通电源时，可选择合盖后仍保持唤醒。
- 提供 English、简体中文、日本語 三种界面语言，可在设置里切换。

## 下载

下载 [ScreenOff.dmg](https://github.com/imetn/ScreenOff/releases/latest/download/ScreenOff.dmg)，然后拖入「应用程序」。

支持 macOS 14 及以上版本的 Apple Silicon MacBook。

## 权限与隐私

只有在开启对应功能时，Screen Off 才会申请系统权限：

- **输入监控**：让自动关屏能区分本机键盘触控板操作与远程输入。
- **辅助功能**：让「关闭输入」在生效期间吞掉本机键鼠事件。
- **合盖后保持唤醒**：注册一个只做一件事的特权守护进程——写入系统睡眠设置。拔掉电源、退出 App，
  乃至 App 被强制结束或崩溃时都会自动恢复。

Screen Off 不读取也不保存按键、指针位置、屏幕内容或远程会话。

应用内没有任何分析 SDK，也不做自有遥测。若你同意，每日的更新检查会附带一份匿名系统信息——macOS
版本、机型、CPU、内存与系统语言——用于判断还需要支持哪些版本。其中不含任何标识符和账号信息，
Sparkle 在首次发送前会征求同意，随时可在「设置 → 通用」里关闭。

## 开源协议

[MIT](LICENSE)
