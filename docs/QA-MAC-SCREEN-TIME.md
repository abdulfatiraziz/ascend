# Mac historical app-usage integration

## Scope and access

This feature reads only this Mac's `/app/usage` rows from the local Knowledge
SQLite database. Connections use SQLITE_OPEN_READONLY, verified with
sqlite3_db_readonly; no source copy, edits, private API calls or TCC modifications
are made. A LEFT JOIN to ZSOURCE excludes rows with nonempty source device IDs.
No website, media, notifications, content or window titles are selected. Reading
is off the main thread with row/count/time bounds and cancellation checks.

Apple's native Screen Time/web framework is not used as a generic app-history
export API. The local schema is undocumented and may change; unknown layouts or
access errors fail visibly and preserve the Ascend archive. Full Disk Access for
the exact Ascend app must be granted manually by the user. QA and fixtures cannot
substitute for that OS grant.

## Data semantics

The Mac source has a stable random local ID and optional source marker in the
existing archive. Old phone records decode without a marker; neither source can
replace the other's device ID. Overlapping per-app intervals are unioned, then
all app intervals are unioned for total app-use time. Day/hour splitting follows
the Mac time zone and handles DST. Gaps remain unknown. This is not full display-on
time, and it is labelled separately from Android screen-on time. No cross-device
totals are computed. Retained historical observations survive source pruning.

## Validation before live access

185 Swift checks passed, including existing Android Java interoperability. New
SQLite fixtures verify source-device/stream filtering, Core Data epoch conversion,
requested-bound clipping, no mutation/source-file creation, unsupported/missing
databases, overlap handling, DST/midnight, no fake zeroes, source separation,
backward decoding, idempotence, and retention-gap preservation. Existing Android
screen-time collection has its separate 11 event-math checks from the prior release.
The native Mac target compiled. Actual source access was initially denied by macOS,
so final live import is pending the user's Full Disk Access grant.

## Live verification — 4 November 2026

The user manually enabled Full Disk Access for the exact installed Ascend app,
reopened it and refreshed. The live dashboard reported 20 days with recorded
Mac app usage within the 28-day query window. The archive contains one distinct
Mac source with 28 unique local day starts; missing intervals remain unknown.
Automatic 15-minute open-app refresh is enabled. A second manual refresh advanced
the displayed query time without adding duplicate days. All saved totals were
within their day bounds and hourly bucket starts were unique. The seven-day phone
source was byte-equivalent after canonical JSON serialization before/after the
Mac refresh. Actual elapsed scheduled 15-minute execution was not independently
observed; startup and repeated manual live import are verified. No personal
application names or per-app usage were copied into these notes.
