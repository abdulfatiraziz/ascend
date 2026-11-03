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
An ignored build/rollback/Ascend-before-menu-fix.app preserves the previous build.
The live process was restarted. ScreenCaptureKit failed (-3811), preventing UI
interaction verification by the agent. No private-data screenshots were taken.

Seven obsolete temporary preview apps and six duplicate sample folders were
moved to Trash. Current sample evidence and the single feature worktree remain.
All 39 baseline hashes from the canonical checkout matched before installation;
its source and pre-existing uncommitted changes were preserved. Live archives,
Android tools, signing key and pairing credentials were not modified by cleanup.

Source remains on codex/body-training. No merge or push was performed.
