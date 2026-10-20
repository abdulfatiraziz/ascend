# Ascend 0.4.1 QA — 18 October 2026

Mac release: **0.4.1, build 6**. Android bridge: **0.1.2, version code 3**.
Release checks: **96 passed, zero failures**
(`build/evidence/checks-0.4.1-release.txt`). Mac strict deep code-sign verification
and Android APK signature verification passed.

## Custom urge triggers

Other now reveals an optional short trigger field. Whitespace is trimmed; an
empty field stays Other. Limits are 40 characters and one line. Choosing a preset
clears the saved custom value. Legacy logs without the new optional field retain
their original values. History, trigger summaries and Patterns timelines use the
custom wording. Automatic AI context continues to exclude the entire urge log.

Native QA used only `ASCEND_DATA_DIR=build/qa-0.4.1`:

- Other reveals a labeled, editable field with a short example.
- Work break saves, appears in history/summary and reopens intact.
- A 41-character value disables Save with a readable message; correcting it
  re-enables Save.
- Switching the saved record to Stress removes the custom field; its persisted
  custom value is absent and the history/summary displays Stress.
- Editor content scrolls independently while Save remains pinned.
- The new Steps help sheet renders the missing-source explanation and checklist.

Three added automated checks cover legacy/default behavior, round trips,
trimmed/blank values, bounds, multiline and mismatched imported values, timeline
display and AI exclusion. The fourth new check covers partial health refresh and
repeat-merge preservation, described below.

Screenshots: `build/evidence/custom-trigger-0.4.1.png` and
`steps-help-0.4.1.png`. These show isolated test data.

## Steps investigation and fix

The personal snapshot initially contained 13 health records and zero steps,
with steps permission granted and no reported error. The user confirmed that
Mi Fitness itself showed steps. REA discovered the existing authorized Pixel 8a
and updated the project-built companion with the same permissions and signing key.

The diagnostic source check then observed one Mi Fitness raw step entry and one
daily aggregate. That export was inspected locally; its nonce did not match the
diagnostic launch request, so it was not imported directly. Native Mac Sync now
continued to require its own fresh matching nonce.

The native transfer exposed a distinct failure: Mi Fitness returned an activity-
energy interval ending 1,285 seconds after the query end. The Mac correctly
rejected it under the existing snapshot bounds, blocking valid steps too.

The bridge now flags the unfinished interval's type and excludes that invalid
record. The Mac retains earlier data for that type and refreshes the valid types.
No timestamp limits were relaxed, no energy value was prorated, and no phone-only
or other-app steps were added. Series samples outside the query window are
excluded while preserving original sample-index IDs.

After the user left the bridge visible, **native Sync now succeeded**:

- 83 refreshed records: 68 heart-rate samples, 14 oxygen readings, one daily step total.
- The Steps card displays **50 steps**, attributed to Mi Fitness.
- One earlier activity-energy record remains, clearly marked as retained after a
  failed refresh. The source interval explanation appears in the type error list.
- The local archive contains 84 unique identities in total, without duplicates.
- Health layout and all eight sidebar destinations fit the observed 1103×752 window.

The new regression check verifies that a failed unfinished type preserves its
previous value while valid steps and heart-rate records import; repeating that
merge stays idempotent, and an actually out-of-window record remains rejected.

REA evidence is under `build/health-research/`: device discovery,
`bridge-steps-update.json`, `steps-diagnostic-launch.json`,
`steps-sync-window.json` and `bridge-interval-fix-update.json`. Local snapshots
include `steps-diagnostic-export.json` and `steps-sync-validation-export.json`.
`build/evidence/health-steps-real-0.4.1.png` contains actual imported health readings;
it is distinct from the synthetic editor screenshots.

## Data protection and limits

The personal tracker was byte-for-byte unchanged through isolated editor QA.
Before/after snapshots are under `build/evidence/personal-before-0.4.1.json` and
`personal-after-0.4.1.json`. After the approved real import, all pre-existing
non-health fields match: goals, habits, check-ins, cycle, urge history, reminders
and routine remain intact. The journal remains empty and no QA trigger was copied
to the personal profile. The document migrated from schema 2 to schema 3 during
that intentional save, and the existing protected import path created a backup.

The bridge needed no new health grants. A notification shade covering its window
was observed to pause a test transfer; a clear timeout retained the previous Mac
archive. Dismissing the shade and leaving the bridge visible resolved this.

The 50-step value is what Mi Fitness shared for this query, not proof that it is
the watch's entire current count. Publication timing remains outside Ascend's
control. Sleep and the other absent types remain absent. No live streaming,
automatic habit completion, notification changes or Gemini calls were introduced.
Exhaustive source-interval variants, long histories and alternate display scaling
remain unverified. Earlier QA limits continue to apply.
