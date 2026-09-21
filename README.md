<h1 align="center" style="text-align: center"><img src="Docs/assets/readme/app-icon-final-1024.png" alt="Screen Off" width="52" align="center" style="vertical-align: middle"> Screen Off</h1>

<p align="center" style="text-align: center">English · <a href="README.zh-CN.md">简体中文</a></p>

<p align="center" style="text-align: center"><strong>Keep your Mac awake with the screen off.</strong></p>

Screen Off is made for vibe coding and remote Mac setups. It turns off the built-in display and keyboard backlight when the MacBook is idle, while keeping the Mac online. With Input Monitoring allowed, remote control does not light the local display; touch the Mac's keyboard or trackpad to restore the previous brightness.

<p align="center" style="text-align: center">
  <img src="Docs/assets/readme/menu-bar-light.png" alt="Screen Off menu bar in light mode" width="46%">
  <img src="Docs/assets/readme/menu-bar-dark.png" alt="Screen Off menu bar in dark mode" width="46%">
</p>

## What it does

- Turn the display off now or automatically after an idle period.
- Keep the Mac awake while remote input leaves the local display dark.
- Restore the previous display and keyboard brightness when local input returns.
- Lock the local keyboard and trackpad and dim the screen with them; unlock by holding Fn + Delete for one second.
- Optionally keep the Mac awake with the lid closed while it is on AC power.
- Available in English, 简体中文 and 日本語, switchable in Settings.

## Download

Download [ScreenOff.dmg](https://github.com/imetn/ScreenOff/releases/latest/download/ScreenOff.dmg), then drag Screen Off into Applications.

Requires macOS 14 or later and an Apple Silicon MacBook.

## Permission and privacy

Screen Off asks for a system permission only when the feature that needs it is turned on:

- **Input Monitoring** lets automatic screen off tell local keyboard and trackpad activity apart from
  remote input.
- **Accessibility** lets the input lock swallow local key and trackpad events while it is engaged.
- **Keeping the Mac awake with the lid closed** registers one small privileged helper that does a
  single thing: write the system sleep setting. It reverts when the power is unplugged, when the app
  quits, and even if the app is force-quit or crashes.

Screen Off does not read or store keystrokes, pointer positions, screen content, or remote sessions.

There is no analytics SDK and no telemetry of its own. If you allow it, the daily update check carries
an anonymous system profile — macOS version, Mac model, CPU, memory and system language — so the
project can tell which versions still need support. It carries no identifier and no account data,
Sparkle asks before it is ever sent, and it can be turned off any time in Settings → General.

## License

[MIT](LICENSE)
