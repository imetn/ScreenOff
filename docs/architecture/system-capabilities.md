# 系统能力与安全边界

## 能力矩阵

| 能力 | 实现机制 | 权限与分发 | 失败策略 | 状态 |
|---|---|---|---|---|
| 阻止空闲睡眠 | IOKit `PreventUserIdleSystemSleep` 断言 | 公共 API | 释放断言并回到系统默认 | 已实测 |
| 合盖保持唤醒 | IOKit `PreventSystemSleep` 断言 + 供电来源监控 | 公共 API，系统限定仅接通电源时生效 | 断电或关闭开关立即释放断言 | 断言已实测，合盖行为待物理验证 |
| 识别物理输入 | `IOHIDManager` 订阅内建键盘与触控板 | 需「输入监控」授权 | 降级为 `CGEventSource` 读数，并在界面明示不可靠 | 已实测 |
| 内建屏幕亮度 | 动态解析 `DisplayServices` | 私有接口、直接分发 | 禁用暗屏功能，不影响唤醒功能 | 已实测 |
| 键盘背光 | 动态解析 `CoreBrightness` 的 `KeyboardBrightnessClient` | 私有接口、直接分发 | 单独禁用，不影响屏幕控制 | 已实测 |
| 登录时启动 | `SMAppService.mainApp` | 公共 API、用户批准 | 保持关闭并显示原因 | 待签名构建验证 |
| 应用内更新 | Sparkle 2 + HTTPS 签名 Appcast + EdDSA | 公司 Developer ID、公证、发布密钥 | 配置或验签失败时拒绝更新 | Feed 与公钥已配置，首个签名 Release 待发布 |

## 关键实测结论

### 软件注入事件无法用事件源区分

`CGEventSource.secondsSinceLastEventType(.hidSystemState, ...)` **会被软件合成事件重置**。
实测中向 `.cgSessionEventTap` 注入一次 `mouseMoved`，`hidSystemState` 与 `combinedSessionState`
两个读数同时归零，因此事件源读数无法用于判断「是否有人在本机操作」。

`IOHIDManager` 直接订阅 HID 设备则不受影响：同一组注入事件触发的回调次数为 0。
所以物理输入判定必须走 `IOHIDManager`，事件源只能作为无授权时的降级路径。

### 合盖保持唤醒不需要特权 Helper

`PreventSystemSleep` 是公共断言类型，系统本身限定它仅在接通电源时生效，
与 `caffeinate -s` 同源。因此首版不安装特权 Helper，也不调用 `pmset disablesleep`，
避免了管理员授权、XPC 接口和租约超时这一整套复杂度。
代价是能力边界由系统决定：拔掉电源后系统会忽略该断言，App 同时主动释放它。

## 强制安全规则

- 亮度与背光修改前必须先读原值；读取失败则不写入。
- 原值同时写入 `UserDefaults` 快照，异常终止后下次启动立即还原并清空快照。
- 供电来源变化时立即重算断言：断电即释放 `PreventSystemSleep`。
- 退出时按「先还原屏幕与键盘，再释放断言」的顺序收尾。
- 私有符号缺失时功能整体不可用，不猜测其他选择器或内存布局。
- HID 回调只更新一个时间戳，不读取键值、坐标或任何输入内容。
- 不安装特权 Helper，不执行任意 shell 命令。

## 分发结论

首版使用 Developer ID 签名、公证和 DMG 直接分发。
内建亮度与键盘背光依赖私有框架，不符合 Mac App Store 沙盒边界，因此不以 MAS 为目标。
后续版本通过 Sparkle 更新普通 App bundle；更新归档仍必须完成 Developer ID 签名与 Apple 公证，
并使用独立的 Sparkle EdDSA 私钥签名。私钥不得进入仓库或托管更新文件的服务器。
