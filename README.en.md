# Screen Off

[简体中文](README.md) · English

Turn the screen off. Keep the Mac online.

Screen Off is a lightweight macOS menu bar utility for Apple Silicon MacBooks.
When a MacBook runs as an always-on remote-control host, Screen Off keeps it awake
and dims the built-in display and keyboard backlight to their minimum whenever there
is no physical input.

## Download

Grab `ScreenOff.dmg` from the [latest release](https://github.com/imetn/ScreenOff/releases/latest),
open it, and drag Screen Off into Applications. The installer is Developer ID signed and
notarized by Apple. Later versions can be checked, downloaded, and installed in-app via Sparkle.

Requirements: macOS 14 or later, Apple Silicon MacBook (built-in display and keyboard).

## Features

- **Keep awake**: prevents idle sleep; visible in `pmset -g assertions`.
- **Keep awake with the lid closed**: a separate assertion that macOS only honors on AC power; it is released automatically when unplugged.
- **Auto screen off**: after 1 minute to 4 hours of idle time, saves the current brightness and drops it to minimum; any physical input restores it instantly.
- **Keyboard backlight off**: follows the display when it turns off, manually or automatically, and is restored together with it.
- **Screen off now** and a **brightness slider** right in the menu bar window.
- **Launch at login** via `SMAppService`, no helper tool.
- **In-app updates** with Sparkle 2, using a signed feed and EdDSA-signed archives.
- **Native settings window** with Features / General / About tabs. The Dock icon appears while the window is open and disappears afterwards.

Idle detection only counts physical keyboard and trackpad input via `IOHIDManager`.
Synthetic events injected by remote-control software do not reset the timer,
so remote sessions do not light up the local screen.

## Permissions

"Auto screen off" needs the system's **Input Monitoring** permission to subscribe to HID events
from the built-in keyboard and trackpad. The callback only updates a timestamp; no keys or
coordinates are read. The system prompt appears the first time you enable the switch, and no
relaunch is needed after granting. Without the permission the feature falls back to the system
event source, the UI states that remote input cannot be distinguished, and offers a shortcut to
System Settings.

## Status

Verified on hardware: assertion creation and release, brightness and backlight read/write/restore,
auto screen off, restore on normal quit, restore after a crash on next launch, and the signed
v0.1.0 → v0.1.1 update path. See the [verification log](docs/reference/verification-2026-09-01.md) (Chinese).

Not yet verified: physical lid-close behavior, fallback when unplugging power, real remote sessions,
and the login-item and Input Monitoring flows on a signed build. Until then, treat
"keep awake with the lid closed" as experimental.

## Development

Requirements: Xcode 26.6, XcodeGen, macOS 14+.

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

Unit tests cover pure logic only (idle-delay steps, preference persistence). They do not launch the
app and need no hardware capabilities:

```bash
xcodebuild -project ScreenOff.xcodeproj -scheme ScreenOff -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions builds and runs the unit tests on every push and pull request. Display, keyboard,
power, and lid behavior must still be verified on a real MacBook; a green build is not a working feature.

The app icon is an Icon Composer document at `ScreenOff/Resources/AppIcon.icon`; the three menu bar
glyphs are template SVGs in `Assets.xcassets`.

Project documentation lives under [docs/](docs/README.md) and is written in Chinese.

## License

Released under the [MIT License](LICENSE).
