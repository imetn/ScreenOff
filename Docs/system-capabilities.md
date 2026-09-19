# System Capabilities and Safety Boundaries

## Capability Matrix

| Capability | Mechanism | Permission and distribution | Failure policy | Status |
|---|---|---|---|---|
| Prevent idle sleep | IOKit `PreventUserIdleSystemSleep` assertion | Public API | Release the assertion, back to system default | Verified on hardware |
| App-controlled display idle timer | IOKit `PreventUserIdleDisplaySleep` + existing physical idle timer | Public API | Release when automatic dimming, remote mode and dim session are all off | Independent acquisition/release verified on hardware |
| Keep awake with lid closed | System-level `SleepDisabled` written by a signed privileged daemon registered through `SMAppService` | Needs one-time approval in Login Items & Extensions; AC power required | Refuse on battery; revert on unplug, on quit, on launch reconciliation, and when the daemon loses its last client | Builds, signs and reaches the approval prompt; approval and the closed-lid run remain outstanding |
| Remote display scaling | CoreGraphics display modes + driver default flag | Public API, built-in display | Reject unidentified defaults, mirroring, unavailable original modes; retain recovery journal | Switch, exit, quit and abnormal-restart restoration verified on the test MacBook |
| Remote Dock settings | Dynamically resolved CoreDock SPI in HIServices | Private API; direct distribution | Capture first, verify readback, roll back failures | Visibility, size and restoration verified on hardware |
| Remote Stage Manager | `com.apple.WindowManager` / `GloballyEnabled` through CFPreferences | Undocumented preference; separate display Spaces required | Probe availability/type/managed policy, restore key absence, verify readback | Both switch states and restoration verified in System Settings on the test host |
| Detect physical input | `IOHIDManager` subscription to the built-in keyboard and trackpad | Needs Input Monitoring; requested when auto screen off is first enabled, reconnects automatically once granted | Degrade to the `CGEventSource` reading, state the unreliability in the UI, and offer a System Settings shortcut | Subscription verified; permission flow awaits a signed build |
| Input lock | `CGEventTap` on `cghidEventTap` that swallows keyboard, trackpad and mouse events; locking also enters the dim session so the screen goes dark | Needs Accessibility; prompted on first use | Refuse to lock and state the reason when permission is missing; re-enable the tap whenever the system disables it; the tap dies with the process | Lock, screen dimming, Fn + Delete unlock and brightness restoration verified on the test MacBook (2026-09-19) |
| Built-in display brightness | Dynamically resolved `DisplayServices` | Private API, direct distribution | Disable dimming; keep-awake unaffected | Verified on hardware |
| Keyboard backlight | Dynamically resolved `CoreBrightness` `KeyboardBrightnessClient` | Private API, direct distribution | Disable only this feature; display control unaffected | Verified on hardware |
| Launch at login | `SMAppService.mainApp` | Public API, user approval | Stay off and show the reason | Awaits a signed build |
| Global screen-off and remote-mode shortcuts | KeyboardShortcuts recorder and Carbon hotkey registration | Public API, no extra permission for shortcuts; local/remote wake still needs Input Monitoring | Leave new shortcuts unassigned; reject system/menu and cross-action conflicts; release independently on clear or quit | Persistence and event tests cover both actions; synthetic keyboard events verified remote activation, Dock/Stage Manager restoration, conflict rejection and clearing on the host. Physical shortcut-to-display verification remains outstanding |
| In-app updates | Sparkle 2 + HTTPS signed appcast + EdDSA | Company Developer ID, notarization, release key | Refuse to update when configuration or signature verification fails | Signed download, replacement, automatic relaunch, legacy identity migration, and dual-source fallback verified |

## Key Findings from Hardware Tests

### Stable application identity

The canonical application identifier is `com.frameflowtech.screenoff`, signed with company team
`PRYY9PKKUP`. Local runs now use a stable Developer ID signature instead of linker-only ad-hoc signing
and replace the installed application after validating and backing up the old bundle. The former
`com.ethan.screenoff` defaults are imported once through an explicit allowlist, including brightness
recovery snapshots. Existing new-domain settings are preserved. Privacy grants remain system-owned
and require authorization for the new identifier; no TCC database is edited.

### Injected events cannot be distinguished via the event source

`CGEventSource.secondsSinceLastEventType(.hidSystemState, ...)` **is reset by synthetic events**.
Injecting a single `mouseMoved` into `.cgSessionEventTap` reset both the `hidSystemState` and
`combinedSessionState` readings to zero, so the event-source reading cannot tell whether someone is
physically operating the machine.

Subscribing to HID devices through `IOHIDManager` is unaffected: the same injected events triggered
zero callbacks. Physical input detection must therefore go through `IOHIDManager`; the event source
serves only as the fallback when permission is missing.

### System sleep, display sleep and backlight dimming

`PreventUserIdleSystemSleep` prevents idle system sleep while allowing display sleep. It does not
prevent lid-close sleep, explicit Sleep, or low-battery forced sleep. The old `PreventSystemSleep`
constant is documented as unsupported/deprecated in Apple's current `IOPMLib.h`; creating an
assertion was never evidence that a MacBook would remain running with its lid closed. `SleepDisabled` — the setting behind `pmset disablesleep` — is the only switch that actually keeps a
MacBook running with its lid closed, and it can only be written as root. Screen Off therefore ships one
single-purpose privileged daemon for exactly that write, and nothing else; see the lid-wake row above for
its failure policy. Apple's supported closed-display configuration remains the alternative that needs no
privileged component at all.

When automatic dimming is enabled and brightness control is available, Screen Off holds a separate
`PreventUserIdleDisplaySleep` assertion so its physical-input idle timer controls when the backlight
is dimmed. For example, a 20-minute app timer is no longer preempted by a 2-minute system display
idle timer. A manual dim session and remote mode also hold this assertion: brightness zero keeps
the display/rendering path available for remote use rather than putting the display to sleep.
When all three owners stop, the assertion is released and macOS resumes its own policy. No global
power settings are edited. These assertions do not bypass locking, a screensaver, forced system
sleep, or remote software's own virtual-display behavior.

### Remote mode transaction

Remote mode is an explicit menu-bar toggle, not remote-session detection. Its Settings tab configures
built-in display default scaling, Dock visibility/size, Stage Manager and backlight behavior.
It temporarily holds system/display idle assertions without rewriting the user's keep-awake setting.
Local physical input can still restore backlight brightness without leaving remote mode.

The complete desktop snapshot is synchronized to `remoteModeRecoverySnapshot` before the first
system write. Each successful restoration removes only its own component from the remaining journal;
failed components remain retryable, including disconnected displays. Normal quit waits for the
in-flight transaction and restoration. On an abnormal restart the app restores, never automatically
re-enables, remote mode. Configuration is locked during an active transaction/session.

Display modes are enumerated with `kCGDisplayShowDuplicateLowResolutionModes` to include HiDPI modes.
The driver-provided default flag selects the target, preferring HiDPI; there is no Mac-model/resolution
table. The journal records the display UUID, logical and pixel dimensions, refresh rate and mode ID.
Restore matches the full description, with the mode ID only a same-boot preference. Mirrored displays
are rejected and absent modes are not replaced by guesses. External/virtual displays are not modified.
Changes use `CGConfigureDisplayWithDisplayMode` and `CGCompleteDisplayConfiguration(.forSession)`;
the permanent user configuration is not rewritten. App-only configuration is unsuitable here because
WindowServer can undo an already-restored mode again when the process terminates.

Dock control resolves only the four CoreDock size/autohide getter/setter symbols from HIServices
at runtime and validates both reads before writing. Missing symbols degrade to an explicit error.
Dock quantizes normalized size to integer icon pixels; readback allows one normalized step (0.01).
No Apple Events, GUI scripting, Dock restart, or additional automation permission is needed. The
System Events approach was rejected after reproducible AppleEvent code-requirement-cache timeouts
on the macOS 27 test host; no system settings were modified by the failed reads.

Stage Manager has no public global enable/disable API: the isolated CFPreferences adapter uses
`GloballyEnabled`, preserves an absent original key, checks policy/type, and reports failures. Both
Dock SPI and Stage Manager must be verified on supported macOS versions; preference readback alone
is not proof of the visible Stage Manager transition. Other Stage Manager options and Spaces settings
are not rewritten.

### Remote mode hardware acceptance (2026-09-12)

On a MacBookPro18,1 running macOS 27.0 (26A428), the signed canonical app switched the built-in
display from 2056 × 1329 (4112 × 2658 pixels, 120 Hz) to its driver-flagged default 1728 × 1117
(3456 × 2234 pixels, 120 Hz), then restored the original mode. Normal quit and forced termination
followed by relaunch both restored the saved display mode, Dock size and Stage Manager setting,
and removed the recovery journal. The QA display mode was then restored to the user's original.

The Dock changed from autohide to visible and back; requested size 0.8 read back as 0.79464287,
and restored to 0.41964287. System Settings independently reflected both Stage Manager states and
the Dock size changes. The app lowered display brightness from 0.9159048 to zero and restored it;
keyboard brightness on this host was already zero. A nonzero keyboard round-trip still needs an
appropriate ambient-light setting. Unit tests cover capture failure, partial rollback, interrupted
sessions, partial recovery, corrupt journals, default-mode selection, and independent power owners.

Live UI toggles were checked against the app's own `pmset -g assertions` entries: keep-awake alone
holds system-idle only; automatic dimming holds display-idle; disabling both releases both.
Remote mode independently acquired both assertions with the general switches off, and released
both on exit. A 20-minute app timer retained its display-idle assertion through a 139-second
observation while the AC system display timer remained two minutes; the display stayed awake.
The system's `pmset -g custom` output was unchanged. This verifies assertion ownership; simultaneous
Universal Control/remote software assertions and local input prevent attributing a passive idle
observation exclusively to Screen Off. Additional OS versions and MacBook sizes remain hardware
compatibility checks, particularly for the undocumented Dock and Stage Manager adapters.

## Outstanding Hardware Checks

- Verify remote mode scaling/restoration on additional MacBook sizes and after display disconnect/reconnect.
- Approve the lid-wake daemon in Login Items & Extensions, then verify end to end: enable on AC power,
  confirm `SleepDisabled` turns 1, close the lid and confirm the Mac stays reachable, then confirm it reverts
  on unplug, on quit, and after force-quitting the app.
- Validate Stage Manager visual transitions on supported macOS versions; its setting is undocumented.
- Complete an end-to-end UU Remote session followed by real local keyboard and trackpad input:
  remote operation must not light the local display or interrupt automatic screen-off.
- On the signed canonical app, verify launch at login and the complete Input Monitoring flow:
  one prompt on enable, reconnection after approval without relaunching, and the settings shortcut
  after denial. Before release, also complete the identity-migration checks in [Releasing](releasing.md).

## Mandatory Safety Rules

- Read the original value before changing brightness or backlight; if the read fails, do not write.
- Write the original value to the `UserDefaults` snapshot as well; restore and clear it on the next
  launch after an abnormal exit.
- Hold system-idle and display-idle assertions independently; release all owned assertions on quit.
- On quit, restore the display and keyboard first, then release assertions.
- If a private symbol is missing, the whole feature is unavailable; never guess other selectors or
  memory layouts.
- The HID callback only updates a timestamp; it never reads key values, coordinates, or any input
  content.
- The lid-wake daemon is the only privileged component. It does one thing—write `SleepDisabled`—accepts
  connections only from this app's code signature, and restores the default when its last client
  disconnects, when launchd stops it, and when the power is unplugged. No other helper, no arbitrary
  shell commands.
- The input lock must never outlive the process: it exists only as a live event tap, is released on
  quit, and is re-enabled immediately whenever the system disables it.
- While input is locked, the unlock gesture stays on screen by default. The hint can be switched off in
  Settings, but the gesture itself never changes.
- Locking input dims the display through the same snapshot-first dim session, so unlocking restores the
  original brightness and clears the snapshot.
- The event tap swallows events without reading their content, and leaves system-defined events alone
  so hardware brightness and volume keys keep working while locked.

## Distribution Conclusion

The first version ships as a Developer ID signed, notarized DMG. Built-in brightness and keyboard
backlight depend on private frameworks that do not fit the Mac App Store sandbox, so the App Store is
not a target. Later versions update the plain app bundle through Sparkle; each update archive must
still be Developer ID signed and notarized by Apple, and signed with a separate Sparkle EdDSA private
key. That private key must never enter the repository or the server hosting the update files.
