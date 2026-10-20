# Ascend 0.5 QA — 18 October 2026

Release: **0.5.0, build 7**. Release checks: **99 passed, zero failures**
(`build/evidence/checks-0.5-release.txt`). Strict deep code-sign verification passed
after the final compact-crop refinement.

## Delivered

The user's three original 458×768 PNG renders replace the earlier faceless body
in Today and the compact menu presentation. Original bytes are preserved; native
view crops hide embedded typography and soft masks blend the edges. The app
does not regenerate the face or claim the portrait is a rotatable 3D model.

Automatic progression is Obsidian below half the earned cycle goal, Titanium
from halfway until the goal is reached, then Ascendant. The cycle goal includes
the configured consistency target. Three stage buttons and Final form provide
cosmetic previews; Live form returns to the current appearance. Fixed settings
remain supported. New plans default to Follow progress.

Transitions use an 850 ms native crossfade. Pointer movement provides bounded
plane tilt without a timer or idle animation. Reduce Motion disables the fade
and tilt. The compact view keeps a still portrait and a closer crop. The former
Three.js/GLB runtime remains as legacy source but is excluded from the app bundle.

## Verification

- All three full-size forms rendered in the native app at 1103×752. Embedded
  labels were hidden, the phase order was correct and task controls stayed aligned.
- Preview Titanium, Preview Ascendant and Live form switched the displayed image
  and accessibility label correctly, while the 0% score stayed unchanged.
- The isolated `build/qa-portraits` tracker remained unchanged through previews.
- The compact Quick check-in panel displayed the new Obsidian portrait; the
  refined crop retained the hairstyle and accessibility announced the stage.
- The user's original compact-clock preference was restored after checking the
  avatar mode. The actual OS menu-bar opening was not separately exercised.
- Settings saved Follow progress; the normal profile now starts at live Obsidian.
- Each packaged PNG matches its supplied original byte-for-byte. Source hashes
  are documented in [avatar provenance](../assets/avatar/abdul/README.md).
- App resource lookup was verified from the signed bundle. Legacy Avatar runtime
  resources are absent from the final app; the native path requires no WebView.

Three added checks cover exact phase thresholds/order, negative/nonfinite values,
preview and fixed-appearance resolution, no evolution from elapsed time, automatic
and legacy fixed appearance validation and backup round trips. Earlier health,
habit, calendar, routine, journal, privacy and AI regressions also pass.

Screenshots under `build/evidence`: `avatar-obsidian-0.5.png`,
`avatar-titanium-0.5.png`, `avatar-ascendant-0.5.png`, `avatar-compact-0.5.png`.
The first three use the isolated profile; the compact screenshot shows the normal
profile's unchanged task state after the appearance setting was applied.

## Personal data and limits

The personal JSON was byte-for-byte unchanged through isolated QA. Before/after
snapshots are `personal-before-0.5.json` and `personal-after-0.5.json` under
`build/evidence`. The only final changed field is `avatarFinish`, intentionally
set to Progress through Settings. Goals, cycle, health, urge logs, journal,
reminders, habits and all check-ins are unchanged.

Existing fixed appearances load intact. Current backups using Progress require
the current app; earlier builds do not recognize that appearance value.

Reduce Motion behavior was checked in code; the global macOS preference was not
changed for QA. Minimum-size windows, alternate display scales and transition
frame timing were not exhaustively measured. Plane tilt cannot show an unseen
side of the head, and no 3D reconstruction or body transformation is provided.
No network, AI, health sync or notification action was introduced by this update.
