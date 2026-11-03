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
