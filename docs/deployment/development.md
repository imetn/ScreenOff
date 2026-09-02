# 本地开发

## 环境

- macOS 14 及以上。
- Xcode 26.6（稳定版；发布脚本同样默认稳定版，需要 beta SDK 时显式设置 `DEVELOPER_DIR`）。
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

## 单元测试

```bash
xcodebuild -project ScreenOff.xcodeproj -scheme ScreenOff -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

`ScreenOffTests` 直接编译 `IdleDelay` 与 `ScreenOffPreferences` 两个纯逻辑源文件，
不以 App 作为 Test Host：不会启动菜单栏进程，不弹授权，不触碰真实偏好
（每个用例使用独立的 `UserDefaults` suite 并在结束时删除）。
新增纯逻辑时优先补到这里；涉及系统能力的行为不写单测，走真机验收。

## 持续集成

`.github/workflows/ci.yml` 在 push 到 `main` 与 Pull Request 时，
于 `macos-26` runner 上执行 Debug 编译与单元测试。Icon Composer 图标需要 Xcode 26 及以上编译，
因此 runner 不能降级到更早镜像。

## 当前验证边界

CI 与单测只证明工程能编译、纯逻辑正确。屏幕、键盘、电源、合盖与授权流程必须分别在真实 MacBook 上验收，
不能以编译或单测通过代替。

