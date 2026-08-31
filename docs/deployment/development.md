# 本地开发

## 环境

- macOS 14 及以上。
- Xcode 26.6 或兼容版本。
- XcodeGen。
- 真实 Apple Silicon MacBook 用于系统能力验证。

## 生成工程

```bash
xcodegen generate
```

`project.yml` 是工程结构的来源；修改源文件或配置后重新生成 `ScreenOff.xcodeproj`。

## 构建与运行

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

其他模式：

- `--debug`：使用 LLDB 启动。
- `--logs`：启动后查看进程日志。
- `--telemetry`：查看 `com.ethan.screenoff` 子系统日志。

构建产物位于 `build/DerivedData/Build/Products/Debug/ScreenOff.app`。

## 当前验证边界

项目骨架阶段只验证工程生成与编译。屏幕、键盘、电源和合盖能力必须在实现阶段分别进行真实设备验收，不能以编译成功代替。

