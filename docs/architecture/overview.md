# 架构总览

## 运行形态

Screen Off 是单进程菜单栏 App，不安装任何特权 Helper。

```text
MenuBarExtra / Settings
          │
  ScreenOffController（唯一状态机，由 AppDelegate 持有）
          │
 ┌────────┼──────────┬──────────┬──────────┬─────────┬─────────┐
 电源断言  物理输入    屏幕亮度    键盘背光    供电来源   登录项      更新
 IOKit    IOHIDManager DisplayServices CoreBrightness IOPS SMAppService Sparkle
```

## 状态所有权

- 用户偏好：持久化到 `UserDefaults`。
- 屏幕与键盘原始亮度：进入暗屏会话时写入 `UserDefaults` 快照，退出会话时清空。
  快照持久化的唯一目的，是让异常终止后的下次启动能够还原。
- IOKit 断言 ID：由 `PowerAssertionService` 持有，关闭功能和退出时释放。
- 菜单栏窗口与设置窗口共享同一个 `ScreenOffController`，不各自复制状态。
- `UpdateController` 只持有 Sparkle 更新器和更新偏好，不接触亮度与电源状态。
- `AppPresentationController` 只协调应用激活策略：设置窗口存在时为 `.regular`，关闭后恢复 `.accessory`。

## 组件边界

- `Views` 只呈现状态、发送用户意图，不直接调用系统 API。
- `Models` 保存偏好与会话状态机。
- `Services` 分别封装电源断言、物理输入、屏幕亮度、键盘背光、供电来源、登录项、窗口激活策略和更新器。
- 私有框架一律 `dlopen` 动态解析 + 能力探测，缺符号只降级不崩溃。

## 暗屏会话

会话由空闲计时或「立即关闭屏幕」触发，键盘背光只跟随屏幕关闭：

1. 读原值失败就不写入，会话不建立。
2. 原值写入快照后才降亮度。
3. 物理输入、关闭开关、系统睡眠或退出都会结束会话并还原。
4. 手动触发后有 300 毫秒固定保护期，用于忽略关闭按钮自身的输入；
   保护期不会被后续输入延长，持续移动鼠标也能正常唤醒。

## 空闲判定

事件驱动为主：`IOHIDManager` 回调更新时间戳，暗屏中的输入直接触发还原。
轮询只负责「空闲到点关屏」，间隔随剩余时间自适应（0.5–5 秒），
未启用任何自动开关时完全不轮询。

## 数据

没有数据库、账号或云端数据。持久化内容仅有用户开关、空闲时长、更新偏好和亮度快照。
网络只用于从配置的 HTTPS Appcast 检查与下载更新。
