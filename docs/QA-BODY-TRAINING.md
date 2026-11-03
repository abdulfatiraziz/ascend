# Body training and offline exercise demos — QA

## Isolation and provenance

Work was built on `codex/body-training`, in a separate worktree over the existing
uncommitted Dr Trust, body dashboard and screen-time code. The original checkout
was checked against a content-hash manifest and remained unchanged. The personal
spec, book source, exported measurements, sign-in material and live data archives
were never copied into the worktree or committed. The generator in Tools/BodySample
writes fictional data only to an empty caller-supplied folder.

## Validation

- 203 AscendChecks passed, including Android Java encrypted-link interoperability;
  the separate 11 Android screen-time event-math checks passed in that script.
- Release `scripts/build-app.sh` and `scripts/build-android-bridge.sh` succeeded.
- Manual measurements: add/edit/delete, cloud merge preservation, profile-less
  first manual reading, legacy IDs, scale-row edit protection and corrupt-file
  preservation tested.
- Goal math, weekly averages, projection, stale/sparse/flat data and aggressive
  deadlines tested. Progression covers normal, small dumbbell and assisted moves.
- Watch matching uses Android platform codes: strength 45, running 33, treadmill
  34, walking 53, cycling 4/5. Unknown codes remain visible. See the platform
  [ExerciseSessionType reference](https://developer.android.com/reference/android/health/connect/datatypes/ExerciseSessionType).
- Weekly adherence, weighted heart rate, easy-walk/late-session distinction,
  low-HR flat-pad exclusion, long low-intensity credit and step-floor accounting
  tested. A manual completion and watch session on a day count once.
- Priority warnings distinguish explicit muscle tags, planned weekly sets and
  hard sets logged so far. They never change the plan. Superset references and
  duplicate exercise pairing are validated. The old exercise-specific Saturday
  suggestions were removed after the spec changed.
- Training files round-trip, reject invalid settings/references, preserve corrupt
  files and write atomically without per-save backups.
- Step blocks do not inflate watch totals. Daily aggregates do not prove a
  particular time-window walk. Unknown steps do not trigger a false low-step
  warning. Workout-step samples support the rails hint only when present.

## Native sample UI

The 1120 px preview and 980 px narrow preview were inspected using generated
sample data, in isolated ASCEND_DATA_DIR folders with live sync disabled. Native
manual-weight save, goal/settings save, exercise reordering, Same as last and
Command–Return set save were exercised. Front/back hard-set maps were rendered
and inspected. The existing Body photo comparison flow is reused; no personal
photos were opened or sent during QA. Sample fixtures intentionally contain no
real photos, so a populated photo comparison was not visually exercised.

Screenshots shown in chat before any commit are under ignored `build/evidence/`:
body-sample-overview.png, body-sample-narrow.png, body-sample-steps.png,
body-sample-map-front.png, body-sample-map-back.png and
body-sample-exercise-demos.png. The screenshot service returns JPEG bytes (despite
those initial output names); content is unchanged. Final capture attempts after
a sample-app restart failed in macOS ScreenCaptureKit, so the final reduced-motion
adjustment was compiled rather than screenshot-verified. The earlier static poses and native playback toggle were visibly verified;
those images were subsequently replaced at the user’s request.

## Generated artwork and Android

The user rejected GymMane's stiff two/three-pose loops. They have been removed
from both apps. Free open libraries were reviewed (desk-break and opengym3d),
but did not provide a consistent redistributable set covering the selected gym
movements. The explicit requested fallback was used: six fictional generated
illustrations with actual transparent alpha, plus decorative GIF variants.

The built-in image-generation tool created each illustration separately. The
incline-press image received a background-removal edit through that same tool.
ffmpeg resized the PNGs and encoded short looping transparent GIFs; the pose
itself never changes. Static art is the default, GIF motion is opt-in and is
labelled decorative rather than a rep demonstration. No personal photos,
measurements, sign-in data or private lift weights were supplied. The prompt
set and processing notes are in Resources/ExerciseDemos/ORIGIN.md.

The Mac and Android players display only local data-URI images with JavaScript,
web bridges and external navigation disabled. Android blocks network loads.
The earlier Bridge 0.8.0 was installed in place with the existing signer and the
user verified that its original player opened and animated. The replacement is
Bridge 0.8.1 / versionCode 19, with unchanged permissions. Replacement Bridge 0.8.1 / versionCode 19 was installed successfully in place;
package version was checked. The PNG/GIF replacement has not yet received an
independent on-device visual confirmation. All six PNGs have real alpha; all
GIFs have 24 frames and transparency. APK and Mac resource bytes match exactly,
and the APK contains no old SVGs. The complete replacement pack is 6.6 MB.

## Limits and next use

The live Mac app/data were not replaced by this worktree preview. Personal plan,
weights and goal checkpoints from the external spec were not seeded into code or
fixtures; enter those through the new UI when adopting this branch. Age-based
intensity and body-fat/lean-mass projections are estimates. Watch workout codes do
not prove incline: the walking-pad rule uses the explicitly named same-day plan.
Mac training logs and body archives have separate backup requirements from the
main tracker export; see USER-GUIDE.md.
