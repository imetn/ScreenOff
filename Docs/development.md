# Local Development

## Environment

- macOS 14 or later.
- Xcode 26.6 (stable). The release script also defaults to the stable toolchain; set `DEVELOPER_DIR`
  explicitly when a beta SDK is required.
- XcodeGen.
- A real Apple Silicon MacBook for verifying system capabilities.

## Generating the Project

```bash
xcodegen generate
```

`project.yml` is the source of truth for project structure. Regenerate `ScreenOff.xcodeproj` after
changing source files or configuration.

## Build and Run

```bash
./Script/build_and_run.sh
./Script/build_and_run.sh --verify
```

Other modes:

- `--debug`: launch under LLDB.
- `--logs`: launch, then stream the process log.
- `--telemetry`: stream the `com.frameflowtech.screenoff` subsystem log.

The build product is `build/DerivedData/Build/Products/Debug/ScreenOff.app`. The run script signs it
with the company Developer ID, validates its bundle identifier and signature, backs up an existing
known Screen Off installation under `build/AppBackups/`, then replaces and launches
`/Applications/ScreenOff.app`. It asks a running app to quit and waits for its restoration work before
replacing it. After installation verification, it unregisters and removes the duplicate build `.app`;
backups remain ZIP files. This keeps local runs on one installed path with a stable code identity.

The default signing identity belongs to company team `PRYY9PKKUP`. Contributors can override
`SCREENOFF_TEAM_ID` and `SCREENOFF_SIGNING_IDENTITY` with their own Developer ID. Unsigned runtime
builds are intentionally unsupported: Input Monitoring grants cannot reliably survive their rebuilds.
Local signed builds are not notarized release artifacts.

## Environment Variables

Screen Off does not depend on environment variables at runtime; the update feed, public key, and
GitHub URLs are compiled into the app's `Info.plist`.

The scripts support these optional overrides:

- `DEVELOPER_DIR`: selects the Xcode toolchain. The build and release scripts default to the stable
  Xcode 26.6; set this explicitly when a beta SDK is required.
- `SCREENOFF_TEAM_ID`: the Developer ID team, fixed to the company team `PRYY9PKKUP` by default.
- `SCREENOFF_SIGNING_IDENTITY`: the full Developer ID Application identity used by local runs;
  defaults to the company identity for `SCREENOFF_TEAM_ID`.
- `SCREENOFF_NOTARY_PROFILE`: the `notarytool` keychain profile name, `ScreenOff-Notary` by default.

The Sparkle private key is stored in the login keychain by the official tools. It is never passed
through environment variables and must never be committed to the repository.

## Unit Tests

```bash
xcodebuild -project ScreenOff.xcodeproj -scheme ScreenOff -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

`ScreenOffTests` compiles the pure-logic sources, `IdleDelay`, `ScreenOffPreferences`, and the shortcut service,
directly instead of using the app as a test host: it does not launch the menu bar process, does not
trigger permission prompts, and does not touch real preferences (each case uses its own
`UserDefaults` suite and deletes it afterwards). Add new pure logic here first; behavior that depends
on system capabilities is not unit-tested and goes through hardware verification instead.

## Continuous Integration

`.github/workflows/ci.yml` runs a Debug build and the unit tests on a `macos-26` runner for pushes to
`main` and for pull requests. The Icon Composer app icon requires Xcode 26 or later, so the runner
cannot be downgraded to an older image.

## Current Verification Boundary

CI and unit tests only prove that the project compiles and that pure logic is correct. Display,
keyboard, power, lid, and permission behavior must each be verified on a real MacBook; a green build
or test run is not a substitute.

## Localization

The app ships Simplified Chinese, English and Japanese. Chinese is the development region and the
Chinese source text is itself the key: `zh-Hans.lproj/Localizable.strings` maps each key to itself,
while `en.lproj` and `ja.lproj` carry the translations.

Two consequences are easy to violate silently, and both have shipped untranslated strings before:

- SwiftUI looks a literal up automatically only where the parameter is a `LocalizedStringKey` — `Text`,
  `Label`, `Button`, `Toggle`, `Picker`, `LabeledContent`, `.help`, `.accessibilityLabel` and the like.
  A Chinese literal passed as a plain `String` argument, assigned to a `String` property, or sitting in
  the second branch of a ternary whose first branch is already wrapped, is never looked up and stays
  Chinese in every language. Those need `String(localized:)`.
- The privileged daemon is a separate process with no localized resources, so it must never produce
  user-facing text. `setSleepDisabled` replies with the raw `IOReturn` and the app turns that code into
  a message on its own side.

Interpolation in a key becomes `%@`, so `"\(title)快捷键"` is stored as `"%@快捷键"` and the interpolated
argument must already be localized when it is passed in. Convert numbers to `String` first: an integer
interpolated directly produces a `"%lld 分钟"` key, which never matches the `"%@ 分钟"` entry in the
table, so the string renders in Chinese in every language.

Before shipping a change that touches user-facing text, confirm that every key in the source exists in
all three tables and that the `%@` count matches on both sides. Scan for any non-ASCII character rather
than for Chinese characters: keys such as `" · Retina"`, `"%@：%@"` and `"%@，%@。%@"` consist only of
punctuation and an interpunct, and scanning for Chinese misses that whole group.

Language names in the picker stay in their own script — English, 简体中文, 日本語 — so nobody has to
read the current interface language to find their own. Switching writes the `AppleLanguages` user
default and takes effect on restart; `AppLanguage.restart()` relaunches through the normal quit path so
brightness, input lock and lid settings are restored first.

## README Screenshots

`Docs/assets/readme/menu-bar-{light,dark}.png` are the two menu-bar shots both READMEs share, one per
appearance. Capture the popover at @2x with the wallpaper still showing through its rounded corners,
then mask it: a **continuous** corner curve of radius 34 px, 37 px of padding on every side, and a
drop shadow of 14 px blur offset 7 px downward at 28 % black.

The corner curve matters more than the radius. macOS draws window corners as squircles, so a plain
circular arc cannot be fitted to them at any radius: too small and the corner tip plus the point
where the arc meets the straight edge both leak wallpaper, too large and the middle of the arc eats
into the window. Use `CALayer` with `cornerCurve = .continuous` rather than
`CGPath(roundedRect:cornerWidth:cornerHeight:)`.

Fit the radius by measuring instead of by eye. For each column x near the top-left corner, find the
first row that is unmistakably window body (on the light shot, luminance above 170 — plain wallpaper
sits near 128 and the window's own shadow darkens it to about 108). Render each candidate mask on its
own and read its curve the same way, then compare column by column: a mask shallower than the measured
boundary in any column leaks, and one much deeper than it everywhere is cutting into the window.

Measured against that boundary, a circular arc of 34 px leaks in three columns — x = 0 and x = 32–33,
exactly the corner tip and the tangent point — while the continuous curve of the same radius leaks in
none and never overcuts by more than 2 px. Verify every corner at several times magnification over a
contrasting background before committing the assets; at full size the leak is invisible, and on a
white README it is not.

## Settings Layout Verification

The four native toolbar tabs are ordered Remote, Feature, General, About: remote work is the main
scenario for this Mac, so that tab comes first. The window is a fixed 520 pt wide, but each tab takes
its own intrinsic height instead of a shared one — the four pages differ too much in content, and one
shared height either leaves About mostly empty or squeezes General into a scroll view. The current
screen's available height still caps it, and the form scrolls internally beyond that. Feature settings retain the discrete
idle-delay slider and a separate brightness/manual-screen control. Remote configuration uses six
separate native rows. The Dock-size switch and labeled 244 pt size slider are distinct settings,
with a standard row separator between them and a percentage beside the slider. The primary remote action
immediately follows the form.
There are no permanent sleep/lid help links or remote help buttons; actionable failures remain visible.
`WholePointHeightLayout` rounds intrinsic heights upward before placing the tab content: a native
form requesting 361.5 pt must receive 362 pt, rather than a 361 pt viewport with a persistent
fractional scroll range. Native forms and the About scroll view retain their normal overflow and
system scroll-indicator behavior. Verify all four tabs and repeated notice appearance/removal in
a native Settings scene; a passing build alone does not prove the scrollbar behavior.

The shared grouped form hides its scroll-content background. Its scroll view extends
under the titlebar; drawing a narrower background produces a rectangular material
boundary when the window becomes active. The window owns the background instead, while the
native tab selection effect and grouped-row backgrounds remain unchanged. Also clip the form to
its SwiftUI content bounds: the native scroll-pocket material can still extend into the titlebar
with a transparent scroll background. This keeps the effect out of the toolbar without changing
content insets or disabling scrolling. Check activation and tab switching in both appearances,
alongside the fractional-height regression above.

General settings provide independent screen-off and remote-mode shortcut recorders. The existing
screen-off preference key is preserved; the remote shortcut is unassigned by default. Both reject
system/menu conflicts and a key used by the other action. Recording suspends hotkeys, and a complete
press/release pair is required after recording before either action fires. Clicking a recorder clears
its current shortcut and waits for a new one; Esc, or a click elsewhere, leaves it unset. Changing and
removing a shortcut are therefore the same gesture, and the field carries no separate clear button.
Input Monitoring is a separate permission for physical-input recognition; it is not required to
register these shortcuts.

The General tab lists a permission only when the feature that needs it is in use and the permission is
not in place. Input Monitoring appears only while automatic screen off is on, and the lid-wake daemon
only while keep-awake-with-lid-closed is on and the system supports the setting. Accessibility is judged
on the permission alone, because Lock Input has no switch and can be triggered from the menu bar at any
time, and because macOS presents its authorization prompt only once — a user who declined it would
otherwise have no way back. Listing a permission that nothing currently needs reads as a fault report
rather than as information. When nothing is pending, one line states that all required permissions are
granted and carries the three individual states in its tooltip, so a permission revoked in System
Settings stays discoverable. Each pending row keeps one short sentence on what the permission is for;
the boundary statement — what it can and cannot see — lives in the tooltip.

The 320 pt menu popover leads with the two mode actions, Remote Mode and Lock Input, as prominent
buttons that turn filled while active. A divider separates them from the persistent-state rows: a
display toggle and a stay-awake row. The display row is labelled "Display" rather than "Turn Off
Display" — a toggle beside an action label reads ambiguously, because "on" would name neither the
screen nor the feature. Automatic screen off follows, with a native idle-duration picker, then Settings
and Quit. Settings carries no ellipsis: it opens a window rather than asking for further input. The
duration picker uses the same discrete values as Settings and is disabled when automatic screen-off is
off. Remote-desktop
configuration remains in Settings. While remote mode owns wakefulness, its effective status is shown
instead of a misleading independent toggle. Both surfaces use the controller's serialized remote action.

About keeps Current Version above Open Source in the right-hand text column. Its repository and
issue-reporting buttons are horizontally centered 20 pt below that content, with remaining space
left below the buttons instead of an expanding spacer above them. The GitHub button uses the unmodified monochrome
Invertocat SVG from [GitHub's official logo assets](https://brand.github.com/foundations/logo),
rendered as a template image for light and dark appearances. The mark belongs to GitHub, Inc.; it
identifies the repository link, does not imply endorsement, and is not covered by the project's
source-code license.
