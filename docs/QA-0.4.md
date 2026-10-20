# Ascend 0.4 QA — 18 October 2026

Release bundle: `build/Ascend.app`, version **0.4.0, build 5**.
Debug and release checks: **92 passed, zero failures**.
Strict deep code-sign verification passed after the final build.
Logs: `build/evidence/checks-0.4-debug.txt` and `checks-0.4-release.txt`.

## Scope

Patterns adds sleep timing, caffeine logging and overall daily energy, with optional
mood, stress and notes. Existing watch sleep/workout records and generic urge logs
are incorporated when present. It introduces no additional imports, permissions,
network calls or automatic habit completion. See [Patterns guide](PATTERNS.md).

## Personal data protection

The real tracker was copied to `build/evidence/personal-before-patterns.json` before
QA. All test saves, synthetic dates and populated comparisons used the separate
`ASCEND_DATA_DIR=build/qa-patterns` profile. The QA process was stopped and the
normal app reopened on Patterns after verification.

The personal tracker was **byte-for-byte unchanged after normal-profile startup**:
17 habits, zero check-ins and all 13 previously imported health records remained.
No fabricated reflection, caffeine entry or historical check-in entered it.
Legacy schema 2 loads as schema 3 in memory; merely opening the app does not
rewrite the file. The next intentional save uses schema 3.

## Automated verification

Nineteen additional checks cover:

- Schema 1/2 defaults, preservation and schema 3 backup round trips.
- Optional ratings, bounds, uniqueness and empty-reflection removal.
- Sleep ordering, wake-date assignment, elapsed duration and asleep-hour bounds.
- Unknown/zero caffeine, finite doses, identifiers and text limits.
- Complete-log totals and unknown values remaining absent rather than zero.
- Manual sleep precedence, longest eligible watch session and restoring source data.
- Exact completed-date ranges excluding today.
- Four comparison groupings, 14 paired dates and five dates per group gates.
- Rest dates, outside-cycle dates and missing scheduled-habit treatment.
- Midnight caffeine windows, inclusive six-hour boundaries and zero-dose exclusion.
- Circular bedtime variation around midnight and undefined means.
- Daylight-saving elapsed duration, timeline ordering and distinct event IDs.
- AI context exclusion and stale-proposal rejection after a journal edit.
- Preservation through habit resets and cycle restart.

Earlier scoring, calendar, routine, reminders, health and AI checks also passed.

## Native verification

| Flow | Result |
| --- | --- |
| Empty Daily story | Missing sleep, caffeine and energy show dashes; incomplete logs stay explicit |
| Caffeine entry | Invalid `NaN` blocks Save; corrected 80 mg entry persists on its own date |
| Daily reflection | Energy, optional mood/stress and completed-log flags save and reload |
| Manual sleep | Overnight 23:00–07:00 accepted; 9 asleep hours rejected inside an 8-hour window; 7.5 accepted |
| Unsaved changes | Close prompts to discard; Keep editing preserves the form |
| Future dates | Next story date disabled today; future timestamps blocked by editor/store validation |
| Delete and Undo | Caffeine deletion confirms; completed empty log displays zero; Undo restores the entry |
| Menu shortcuts | Daily check-in, Log caffeine and Patterns appear; quick-panel check-in opens today's desktop editor |
| Completed-date charts | Today excluded; empty coverage remains empty; 21 synthetic dates render with gaps and correct units |
| Comparison cards | Explicit metric labels, group counts and fixture averages match the expected values |
| Main window | Daily and trends layouts reviewed at 1358×895; eight sidebar destinations and Settings visible |
| Normal profile | Real cycle restored on launch; Patterns has no synthetic journal data |

The synthetic comparison fixture has alternating 6/8-hour windows, energy 2/4,
completed urge/caffeine logs and no habit check-ins. It yields 21 paired energy
and urge dates (10/11 groups) and 20 paired caffeine dates (10/10 groups).
These are test results, not personal findings.

Final release screenshots under `build/evidence`, showing the isolated fixture:

- `patterns-daily-synthetic-release.png`
- `patterns-trends-synthetic-release.png`
- `patterns-comparisons-synthetic-release.png`

## Limits

- Minimum-size window resizing could not be reliably exercised through the UI
  automation surface; only the stated window size is verified in this release.
- The real health archive currently has heart-rate, oxygen and activity-energy
  records, without a sleep/workout session. Watch sleep selection uses deterministic
  source fixtures; no new real overnight transfer was available for this QA.
- Long histories, accessibility screen-reader interaction and alternate display
  scaling were not exhaustively tested. Chart accessibility data was inspected.
- New journal records remain local and excluded from automatic Gemini context.
  Live Gemini, notification banners and phone sync were not rerun for this feature;
  their previous QA limits remain in [QA 0.2](QA-0.2.md) and [QA 0.3](QA-0.3.md).
- Comparisons are exploratory associations. Sample gates reduce sparse displays;
  they do not establish statistical significance or causation.
- Nutrition, weight/waist, hourly steps and additional HRV/resting-heart-rate imports
  remain outside this first set.
