# Ascend 0.3 QA — 18 October 2026

Release bundle: `build/Ascend.app`, version 0.3.1, build 4. Release checks:
**73 passed, zero failures** (`build/evidence/checks-0.3-release.txt`).
Mac strict deep code-sign verification and Android APK signature verification passed.

## Personal data

The real tracker was copied to `build/evidence/personal-before-health-upgrade.json`
before QA. All synthetic urge/health checks used `ASCEND_DATA_DIR=build/qa-health`.
No real check-ins, goals, dates or urge records were reset or fabricated. The
personal tracker remained byte-for-byte unchanged through release QA and initial
normal-profile startup. After the user granted phone permissions, the approved
real sync added health records and migrated the document to schema 2. Goals, cycle,
habit IDs and all check-ins were verified against the pre-sync snapshot. Synthetic
readings never entered the personal profile.

Schema 1 backups migrate in memory to schema 2, with legacy urge IDs, timestamps,
outcomes and check-ins preserved. New saves use generic urge keys/outcomes. The
old seeded habit label displays as Stay intentional. Future schemas are rejected.
Older application builds should not be used to edit the new format. Existing raw
backup files and user-written notes are not erased or rewritten by this migration.

## Device findings using REA

- REA 6.5.0 and official ADB 37.0.1 discovered the authorized Pixel 8a wirelessly.
- Installed companion: Mi Fitness, `com.xiaomi.wearable`, version 3.59.1i.
- Its Health Connect permissions include granted writes for heart rate, steps,
  sleep, oxygen saturation, distance, activity energy, speed, elevation and exercise.
- REA acquired the complete installed APK split set with digests and performed
  package/artifact inspection. Artifacts remain under `build/health-research`.
- Normal `run-as` access to Mi Fitness was unavailable because it is not debuggable.
  No private-database bypass, root, interception or credential extraction was used.
- The new project-built Ascend Bridge APK installed and launched successfully via REA.

Evidence records include `packages-wearable.json`, `mi-fitness-package.json`,
`mi-fitness-acquisition.json`, `apk-inventory.json`, `bridge-install.json` and
`bridge-launch.json`. `mi-fitness-dumpsys.txt` contains the observed permission
state. Package names or declared permissions do not prove the watch generated
measurements of every type.

## Automated additions

Ten added checks cover generic urge migration, optional custom labels, bounds,
future backup rejection, Health Connect source/nonce/time validation, duplicates,
invalid values, permission rejection, idempotent imports, corrections/deletions,
older/denied/failed record retention, denied-access errors, local backup round trips,
AI exclusion, score independence, reset/restart preservation and local date grouping.
Earlier routine/calendar/AI/reminder regression checks also pass in this release.

## Native checks

| Flow | Result |
| --- | --- |
| Health setup and discovery | Pixel 8a appears with a readable Wi-Fi label; install/sync/setup controls fit |
| Fresh phone export without permissions | Native companion produced a matching snapshot; Mac rejected the import with a clear permissions message |
| Permission rejection persistence | No successful empty sync, no health overwrite and no habit check-in created |
| First permitted real sync | 13 records saved: 10 heart-rate samples, two oxygen readings and one activity-energy interval; no Health Connect errors |
| Phone asleep / foreground guard | No fresh snapshot published; Mac showed an unlock/retry error and re-enabled Sync; prior 13 records retained |
| Repeated real sync | Same 13 stable, unique records retained; no duplicate check-ins or health records |
| Real import safety | Dated backup verified; stable unique IDs; goals/cycle/habit IDs/check-ins preserved; local archive and UI matched |
| Health dashboard with synthetic fixture | Nine cards, values/units, sample average/range and chart rendered; independent scrolling checked |
| Health date navigation | Previous date showed missing data rather than carrying readings across dates; next returned to today |
| Health future date | Next-day action disabled on today |
| Generic urge log | Timestamp saved; custom Distraction label and Let it pass outcome persisted |
| Urge editor | Optional label/intensity/trigger/outcome/note and pinned Save checked |
| Neutral wording | Menu, header accessibility/help, urge views and legacy goal row checked without the old explicit wording |
| Navigation at 1103×752 | All seven sections and settings remain visible |
| Score isolation | Synthetic health archive and urge entry left habit check-ins empty |

Evidence images, **all health readings synthetic and isolated from the personal profile**:
`health-dashboard-synthetic-release.png`, `health-chart-synthetic-release.png`,
`generic-menu-release.png` under `build/evidence`.

## Pending and limitations

- A background sync delay was observed; foregrounding Ascend let it finish.
  Version 0.3.1 holds a user-initiated macOS activity during transfer to prevent
  App Nap delays. The bridge now requires an interactive, unlocked, focused screen
  before reads and publication, and holds the screen on only during transfer.
  This avoids publishing a misleading empty result after losing foreground access.
- The user explicitly granted Health Connect permissions on the phone. The first
  permitted import has now been verified end-to-end. Source records had no device
  model metadata; Mi Fitness attribution is verified, exact watch attribution is not.
- Supported metrics depend on what this watch/Mi Fitness actually writes. This is
  a manual historical sync of the latest 14 days, not continuous BLE/live heart rate.
- Granted-permission reads and the Mac handoff/save/display path were verified
  with real records. Large-page pagination, source changes, prolonged locked-phone
  behavior and cross-device source overlap remain untested end-to-end. These merge
  edge cases use deterministic fixtures.
- Steps use Health Connect aggregation with the Mi Fitness source filter. Other
  interval metrics are grouped by start day; sleep is grouped by its ending day.
  Session windows are distinguished from reported asleep stages.
- No automatic habit completion, dietary calorie logging or medical inference.
- Companion scope is Android 14+, foreground, read-only, no internet permission.
  Debug authorization and health grants are controlled by the phone's owner.
- Previous QA limits for notification banners, OS menu-bar opening and live Gemini
  testing remain; see [QA 0.2](QA-0.2.md).

Setup and operational details: [Health sync guide](HEALTH-SYNC.md).
