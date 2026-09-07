# System Capabilities and Safety Boundaries

## Capability Matrix

| Capability | Mechanism | Permission and distribution | Failure policy | Status |
|---|---|---|---|---|
| Prevent idle sleep | IOKit `PreventUserIdleSystemSleep` assertion | Public API | Release the assertion, back to system default | Verified on hardware |
| Keep awake with lid closed | IOKit `PreventSystemSleep` assertion + power source monitor | Public API; macOS honors it only on AC power | Released immediately when unplugged or switched off | Assertion verified; lid behavior awaits physical verification |
| Detect physical input | `IOHIDManager` subscription to the built-in keyboard and trackpad | Needs Input Monitoring; requested when auto screen off is first enabled, reconnects automatically once granted | Degrade to the `CGEventSource` reading, state the unreliability in the UI, and offer a System Settings shortcut | Subscription verified; permission flow awaits a signed build |
| Built-in display brightness | Dynamically resolved `DisplayServices` | Private API, direct distribution | Disable dimming; keep-awake unaffected | Verified on hardware |
| Keyboard backlight | Dynamically resolved `CoreBrightness` `KeyboardBrightnessClient` | Private API, direct distribution | Disable only this feature; display control unaffected | Verified on hardware |
| Launch at login | `SMAppService.mainApp` | Public API, user approval | Stay off and show the reason | Awaits a signed build |
| Global screen-off shortcut | KeyboardShortcuts recorder and Carbon hotkey registration | Public API, no extra permission for the shortcut; local/remote wake still needs Input Monitoring | Leave unassigned by default; reject recording conflicts; release on clear or quit | Persistence/event tests and host registration, replacement, conflict, clear, and shutdown probes passed; physical shortcut-to-display cycle awaits manual verification |
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

### Keeping awake with the lid closed needs no privileged helper

`PreventSystemSleep` is a public assertion type, and macOS itself limits it to AC power, the same
mechanism `caffeinate -s` uses. The first version therefore installs no privileged helper and never
calls `pmset disablesleep`, avoiding admin authorization, XPC interfaces, and lease timeouts entirely.
The trade-off is that the capability boundary is set by the system: once unplugged, macOS ignores the
assertion and the app releases it proactively as well.

## Outstanding Hardware Checks

- Close the lid and unplug power on a real MacBook. If it still sleeps without an external display,
  restrict the feature to supported configurations and align the README wording.
- Complete an end-to-end UU Remote session followed by real local keyboard and trackpad input:
  remote operation must not light the local display or interrupt automatic screen-off.
- On the signed canonical app, verify launch at login and the complete Input Monitoring flow:
  one prompt on enable, reconnection after approval without relaunching, and the settings shortcut
  after denial. Before release, also complete the identity-migration checks in [Releasing](releasing.md).

## Mandatory Safety Rules

- Read the original value before changing brightness or backlight; if the read fails, do not write.
- Write the original value to the `UserDefaults` snapshot as well; restore and clear it on the next
  launch after an abnormal exit.
- Recompute assertions immediately when the power source changes: unplugging releases
  `PreventSystemSleep`.
- On quit, restore the display and keyboard first, then release assertions.
- If a private symbol is missing, the whole feature is unavailable; never guess other selectors or
  memory layouts.
- The HID callback only updates a timestamp; it never reads key values, coordinates, or any input
  content.
- No privileged helper, no arbitrary shell commands.

## Distribution Conclusion

The first version ships as a Developer ID signed, notarized DMG. Built-in brightness and keyboard
backlight depend on private frameworks that do not fit the Mac App Store sandbox, so the App Store is
not a target. Later versions update the plain app bundle through Sparkle; each update archive must
still be Developer ID signed and notarized by Apple, and signed with a separate Sparkle EdDSA private
key. That private key must never enter the repository or the server hosting the update files.
