# Diet plan — implementation and QA

Implemented on codex/body-training over the preserved body/sync prerequisites.
No source in the original checkout was overwritten and no push/merge was made.

## Implementation

- Optional weekday target overrides on HabitRevision; nil retains legacy behavior.
  Validation checks weekday indices, units, finite/nonnegative bounds and ordering.
  A validated diet update revises the existing calorie habit from today, preserving
  pre-today revisions and IDs, and enables all seven scheduled days.
- Resolved daily targets feed habit scoring, metric labels, Meals totals, phone
  habits/summary, assistant context and the maintenance card.
- Optional DietPlan in TrackerDocument, with validated editable meal windows,
  portions, planned kcal/protein, sweet choices, food references and checkpoints.
- Monday budget uses confirmed meals or fallback manual calorie check-ins once
  per day. Coverage and missing-log limitations are visible.
- Explicit Sweet/Café tagging. Café replacement includes a half-hour lead window;
  a tagged sweet outside the configured window blocks the linked check-in without
  mutating its manual completion. Effective date prevents pre-plan blocking.
- Gram/table/spray calculations create editable, confirmed photo-free meals.
  Photo estimation excludes those entries, and meal thumbnails handle no photo.
- Checkpoint line/diamonds in Body and status from equal-weight daily averages in
  the trailing week ending at the latest checkpoint, with two dates required.
- Removed the temporary app-local F7 suppression after the user identified a
  laptop stand pressing the external keyboard's function keys.

## Verification

- 228 Swift checks passed, including the real headless Java encrypted-link client.
- 11 Java screen-time event-math checks passed.
- 15 new diet checks cover legacy decoding, history/ID preservation, round trips,
  invalid overrides, atomic/idempotent setup, phone target parity, Monday budgets,
  meal windows/café, sweets boundaries/timezone/undo behavior, gram/oil calculations,
  no-photo meals, plan validation and daily-average checkpoint coverage.
- Release scripts/build-app.sh passed; installed app signature and executable
  hash matched the built artifact.
- Setup CLI round-tripped a fictional archive with meals, notes and habits intact.
- Native SwiftUI/AppKit render from generated data was inspected and shown before
  committing. Screenshot: ignored build/evidence/diet-sample.png. This verifies
  rendered layout; interactive editor clicks were not exercised through computer
  control. An input-formatting issue in numeric editor fields was corrected before
  the final build. The sample has no real photos or personal measurements.

## Private setup and deployment

The existing pinned diet note supplied the private setup. The local-only prepared
JSON was placed in ignored build/ with owner-only permissions. It was not staged,
copied into fixtures or shown in screenshots. Existing calorie/protein/sweets habits
and the source note were reused; no duplicate habits/notes were created. The source
note's meal windows, portions, sweet list, references and checkpoints remain editable.
Missing spray calibration was left unset. Reference nutrient fields absent from the
note use zero and should be completed before relying on all macro totals; the UI
makes that limitation visible. Ranged references use a midpoint as a planning estimate.

The live app was closed before setup. AscendDietSetup validated the complete
candidate, checked for concurrent file changes and made a one-time backup before
an atomic write. Deployment verified unchanged meal entries, notes, goals, habit IDs,
and all pre-today check-ins/revisions. UUID casing normalization was accounted for
in the deployment verification; a first comparison rejected casing differences and
rolled back safely before the successful attempt. App/data rollback backups were
retained. The app was left closed after installation; no private-data screenshots
were captured. The Android APK was not changed for this feature: today's resolved
budget is delivered by the existing phone sync protocol on the next successful sync.

## Limits

Meal type tagging and plan editing are Mac UI features in this change. Android
uses the existing daily target summary; it does not gain a diet-plan editor here.
Untyped meal photos are not automatically classified as sweets. Template edits can
reassign tagged historical meals since the diet start date; numeric habit history
is revisioned separately. Weight checkpoints are observational and never modify
calorie or exercise targets. A live phone refresh and interactive Mac editor session
have not been independently verified after this installation.
