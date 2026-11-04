# Menu focus and preview cleanup

## Changes

- Use a native status menu. Open/activate the main window after menu tracking ends.
- Keep rich quick check-in inside the main window and queue its next destination
  or editor until sheet dismissal finishes, replacing fixed-delay handoffs.
- Remove the offscreen sample-render hook, which built an extra MainView.
- Hide the menu-bar extra in isolated ASCEND_DATA_DIR preview launches.
- Run the Java encrypted-link test headless. Its ImageIO fixture used AWT and
  could otherwise register a Java Dock application with no usable window.

## Validation and rollout

The user reported the error sound when opening Ascend and pointed to the Java
Dock icon as another trigger. No explicit click or beep call was found. These
changes address the identified focus hazards; audible resolution awaits user
confirmation and is not established by automated checks.

All 213 Swift checks passed with the real Java encrypted-link client running
headless; the 11 Java screen-time math checks also passed.
The Mac release build and strict code-signature verification passed. The updated
app was copied to the existing build/Ascend.app path in the canonical checkout.
An ignored build/rollback/Ascend-before-menu-fix.zip preserves the previous build.
The live process was restarted. ScreenCaptureKit failed (-3811), preventing UI
interaction verification by the agent. No private-data screenshots were taken.

Seven obsolete temporary preview apps and six duplicate sample folders were
moved to Trash. Current sample evidence and the single feature worktree remain.
All 39 baseline hashes from the canonical checkout matched before installation;
its source and pre-existing uncommitted changes were preserved. Live archives,
Android tools, signing key and pairing credentials were not modified by cleanup.

Source remains on codex/body-training. No merge or push was performed.

## Confirmed input cause

The user reported that the first menu-focus update did not stop the sound.
An LLDB trace then captured 102 NSBeep calls, all through NSDatePicker keyDown
and NSWindow keyDown. A second trace captured over 200 repeated F7 events
(keyCode 98 / kVK_F7), at roughly 12 per second. The trace recorded function
names, key codes, modifier flags and repeat flags only, never typed text.
The debugger was detached and the user was asked to press/release F7 (or Fn-F7)
to clear the repeated input.

FunctionKeyFilter locally consumes bare F7 keyDown events, which have no Ascend
binding. Modified shortcuts, other keys and system-defined media events pass
through unchanged; other apps and global sound preferences are unaffected.

Six old rollback app bundles were subsequently archived as verified ZIPs under
the canonical build/rollback folder; their original app bundles were moved to
Trash to reduce duplicate app registrations. The F7-filter release build passed,
was signed and installed at the existing app path, and was reopened. Audible
resolution is pending user confirmation after this second update.

## Rollback after wider menu reproduction

The user clarified that File/Edit/Help and system menus outside Ascend also
beeped. Their supplied recording showed Codex and macOS menus. The latest
Ascend trace counted 172 filter invocations and zero NSBeep calls, so the
app-local workaround did not resolve the system-wide symptom.

Ascend, LLDB/debugserver and the Codex computer-control helper were stopped.
Computer use was reset and has not been restarted. The user still reproduced
the sound. Read-only CoreGraphics queries reported F7 held in both HID and
combined session state after those processes exited. The initiating source
has not been established; no global event monitor permission was requested.
No keyboard mappings, system sound preferences, input permissions or security
settings were changed. A save-work-and-restart step was recommended.

The deployed canonical app was restored from build/rollback/Ascend-before-menu-fix.zip
as a fresh bundle. Its code signature and exact executable hash were verified
against the archived original. It remains closed. App data archives were not
modified by this rollback. Feature and diagnostic commits remain in the isolated
branch; no push or merge was performed. Earlier audible-resolution statements
are superseded by this failed verification and rollback.

## User-identified physical cause

The user subsequently supplied photos and identified a laptop stand resting on
the external keyboard's function keys. This explains the repeated F7 observation.
The temporary FunctionKeyFilter was removed in the diet-plan build. The earlier
app-level fixes were not evidence of a software root cause. The diet update was
built and installed separately after this clarification.
