# 真机验证记录 · 2026-09-01

机型：Apple Silicon MacBook，内建屏幕与内建键盘，验证期间接通电源。
构建：Debug、未签名（`CODE_SIGNING_ALLOWED=NO`）。

## 通过项

| 项目 | 方法 | 结果 |
|---|---|---|
| 保持唤醒断言创建 | `pmset -g assertions` | 出现 `PreventUserIdleSystemSleep named: "Screen Off: keep awake"` |
| 合盖断言创建 | `pmset -g assertions` | 出现 `PreventSystemSleep named: "Screen Off: keep awake with lid closed"` |
| 断言释放 | 正常退出后复查 | 两条断言全部消失 |
| 屏幕亮度读写 | `DisplayServices` 读 → 写 → 读回 | 0.4988 → 0.05 → 读回一致 → 还原成功 |
| 键盘背光读写 | `CoreBrightness` 读 → 写 → 读回 | 0.3023 → 0 → 还原成功 |
| 自动关屏 | 开发阶段用 5 秒阈值等待 9 秒 | 亮度 0.4988 → 0，快照正确写入；产品档位从 1 分钟起 |
| 正常退出还原 | 退出 App 后复查 | 亮度还原 0.4988，快照清空，断言释放 |
| 异常终止还原 | `kill -9` 后重启 App | 崩溃时亮度仍为 0、快照保留；重启后立即还原 0.4988 |
| 菜单栏图标三态 | 截图比对 | 空心 / 对角切分 / 实心，随状态正确切换 |
| 设置窗口结构 | 实际窗口截图与辅助功能尺寸读取 | 功能 / 通用 / 关于三页完整，窗口为 520 × 369 pt，设置内容列 392 pt 居中 |
| Dock 生命周期 | 打开与关闭设置窗口前后读取进程属性 | 打开时显示 Dock 图标；关闭后恢复后台 App，菜单栏与进程继续存在 |
| 菜单栏窗口 | 实际截图检查 | 304 pt 紧凑宽度；分组使用间距与分隔线；设置与退出为放大的灰色图标按钮 |
| Sparkle 集成 | 构建产物检查 | Sparkle 2.9.6 已嵌入，HTTPS Feed、公钥与双重验签策略已配置；真实升级待首个签名 Release |

## 关键否定结论

向 `.cgSessionEventTap` 注入一次 `mouseMoved` 后：

```
注入前  物理=73.45  合成=73.48
注入后  物理=0.30   合成=0.29
```

`CGEventSource` 的 `hidSystemState` 与 `combinedSessionState` 同时归零，
**事件源读数无法区分软件注入**。原方案中「用事件源判断物理输入」的假设不成立。

同一组注入下 `IOHIDManager` 回调次数为 0，且能匹配到内建设备
（`Apple Internal Keyboard / Trackpad [SPI]` × 3），因此改用 `IOHIDManager` 作为主路径。

## 待验证

- 合盖后的实际保持行为：需要物理合盖 + 远程会话确认，断言本身已就位。
- 拔掉电源后的回退：需要物理拔线确认 `PreventSystemSleep` 被释放。
- 物理输入唤醒屏幕：需要真人在本机键盘或触控板操作。
- 登录时启动：`SMAppService` 在未签名构建上不代表最终行为，需签名后验证。
- UU 远程会话下的端到端表现：需要真实远程连接。

## 状态归还

验证结束后已确认：屏幕亮度 0.4988、键盘背光 0.3023，均为验证前原值；
无残留断言；测试期间写入的偏好已全部删除。
