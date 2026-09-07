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
`/Applications/ScreenOff.app`. This keeps local runs on one installed path with a stable code identity.

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

## Settings Layout Verification

The three Settings tabs use a shared 324 pt minimum content height, with additional room for
capability notices and a maximum based on the current screen's available height.
`WholePointHeightLayout` rounds intrinsic heights upward before placing the tab content: a native
form requesting 361.5 pt must receive 362 pt, rather than a 361 pt viewport with a persistent
fractional scroll range. Native forms and the About scroll view retain their normal overflow and
system scroll-indicator behavior. Verify all three tabs and repeated notice appearance/removal in
a native Settings scene; a passing build alone does not prove the scrollbar behavior.

The shared grouped form hides its scroll-content background. Its 392 pt scroll view extends
under the 520 pt titlebar; drawing that narrower background produces a rectangular material
boundary when the window becomes active. The window owns the background instead, while the
native tab selection effect and grouped-row backgrounds remain unchanged. Also clip the form to
its SwiftUI content bounds: the native scroll-pocket material can still extend into the titlebar
with a transparent scroll background. This keeps the effect out of the toolbar without changing
content insets or disabling scrolling. Check activation and tab switching in both appearances,
alongside the fractional-height regression above.

About keeps Current Version above Open Source in the right-hand text column. Its repository and
issue-reporting buttons are horizontally centered at the bottom, with a 20 pt bottom inset and an
expanding spacer of at least 24 pt above them. The GitHub button uses the unmodified monochrome
Invertocat SVG from [GitHub's official logo assets](https://brand.github.com/foundations/logo),
rendered as a template image for light and dark appearances. The mark belongs to GitHub, Inc.; it
identifies the repository link, does not imply endorsement, and is not covered by the project's
source-code license.
