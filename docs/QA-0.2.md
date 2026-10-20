# Ascend 0.2 QA — 18 October 2026

Release: `build/Ascend.app`, version 0.2.0, build 2, locally ad-hoc signed.
`codesign --verify --deep --strict` passed. The release core executable passed
**63 checks with zero failures**. No live Gemini request was made.

## Isolation and data preservation

Native feature tests used `ASCEND_DATA_DIR=build/qa-next`, with synthetic routine
times and urge entries. Earlier calendar/reset/recovery tests used `build/qa-calendar`.
No personal entries were created, reset or restarted during QA. Personal tracker bytes
were compared with `build/evidence/personal-before-next-features.json` before final
handoff and again after opening the normal release profile: exact match.
Existing history and initial plan were preserved. The normal release app was left open.

## Automated coverage

- Existing 27 checks: recurring and numeric scoring, 75% rounding, historical
  revisions, goal windows, archives, rest/reset/restart, milestones, legacy loading,
  leap days, DST, reminder planning and avatar progress.
- 36 new checks: routine phase boundaries, midnight crossing, invalid windows,
  unconfigured state, next-event rollover, timed revisions, rest days and DST.
- Urge decoding/round trips, duplicate and invalid records, timestamp/length limits,
  and independence from habit scoring.
- AI operation whitelist, bounded batches, new goal/habit references, immutable
  previews, all-or-nothing rejection, stale document/day rejection, date and metric
  validation, history-preserving edits, no-op edits and restart behavior.
- AI context exclusions, key placement, model/key/prompt validation, malformed and
  truncated output, HTTP failures, mocked end-to-end proposals and cancellation.

## Native checks

| Flow | Result |
| --- | --- |
| Desktop navigation and routine at 1103×752 | All six destinations and primary actions visible; clock and agenda scroll independently |
| Routine setup | Example state explicit; saving config persists; 135→120-minute wind-down recalculates 20:45→21:00 before 23:00 bed |
| Habit times | Timed tasks appear in the agenda and dial; untimed tasks remain in Anytime |
| Clock | Current time/phase, next task and compact representation rendered |
| Urge quick log | Timestamp saved immediately without completing No smoking |
| Rapid double-click | One additional urge record; Undo returned to prior count |
| Urge details | Intensity, Coffee trigger, Smoked outcome and synthetic note persisted |
| Urge delete/Undo | Confirmation shown; Undo restored full details |
| AI drawer | Examples, connection state, privacy text and composer fit; Send disabled without setup |
| AI settings | Secure key field; invalid model rejected; closing unsaved edits offers discard protection |
| Compact panel | Clock/avatar switch, next event, Remaining/All, urge log, details and Undo checked |
| Save failure | QA folder temporarily obstructed; error appeared and existing memory/disk record remained intact |
| Save retry | Obstruction removed and original QA folder restored; Settings Retry saved and cleared error |
| Unchanged edits | Fixed redundant revisions/Undo consumption; core regression checks passed |

Earlier native calendar, reset, restart, editor validation, backup recovery and local
notification delivery checks are recorded in [the first-pass report](../build/evidence/verification.md).
The earlier write-failure limitation is superseded by the successful test above.

Screenshots from the isolated release profile:

- [Routine clock](../build/evidence/routine-release.png)
- [Compact clock panel](../build/evidence/menu-clock-release.png)
- [Assistant drawer](../build/evidence/assistant-release.png)

## Remaining verification limits

- No API key was supplied. Actual Keychain save/read and live Gemini authentication,
  model availability and generated proposals require the user's key. The request,
  response, validation and application pipeline was tested with injected responses.
  No credentials, tracker content or urge data were sent to Google during QA.
- Compact UI was tested through Quick check-in, which uses the same view as the
  menu bar panel. Automated status-item opening was not repeated.
- Native notifications were previously confirmed in Notification Center; Focus and
  OS settings may suppress banners. Reminders cover 30 days and refresh on app
  activation/data changes. They remain off in the tested profile.
- Undo lasts until the next successful edit or app quit. Dated backups remain available.
- This is targeted regression and edge-case QA, not exhaustive testing across all
  macOS versions, displays, accessibility modes or hardware.
