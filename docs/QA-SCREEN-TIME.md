# Screen-time sharing — 2026-11-03

## Design

Optional Android Usage access, with sharing disabled by default. The new
`/v1/screentime` endpoint uses the existing paired AES-GCM envelope, freshness and
replay protection. Older phones omit the optional envelope field. An older Mac's
unsupported endpoint does not abort the new phone's other uploads.

The collector reads seven local calendar days plus one lookback day for state.
Only matched screen-on/off intervals (or a known ongoing interactive interval)
are counted. Unknown prefixes/restart gaps are incomplete. Activity lifecycle
intervals are unioned per package and intersected with screen-on intervals;
separate apps may overlap. Day/hour splitting uses the phone time zone and handles
23/25-hour DST days. No class names or content are transmitted. Query/row/event
limits abort the screen read rather than publishing a truncated result.

The Mac validates dates, totals, durations, source identity, freshness and packet
limits; saves to a separate atomic archive; preserves prior history on denied,
disabled, unavailable or partial reads; and retains roughly 90 days during sync.
Main tracker/watch schemas and credentials are unaffected. Screen-time background
sync has a separate opt-in and does not require Health Connect background access.

## Validation

178 Swift checks passed, including encrypted Swift and Java screen-time transfers,
replay/wrong-key/stale rejection, validation/storage/permission-state behavior and
existing phone/health/meal/medicine compatibility. 11 pure Java event-math checks
passed, covering overlaps, midnight, DST, restart gaps, ongoing sessions and zero
versus unknown observations. The Android sources compiled against SDK 36 and the
native Mac dashboard compiled. Device installation/live permission/sync checks
are recorded below when completed.

## Device rollout and first live transfer

- Built Bridge 0.7.0 (versionCode 17) using the original signing key; certificate
  digest matched the previous APK. Installed with an in-place update, preserving
  app UID, pairing and existing Health Connect permissions.
- Rebuilt/signed/reopened the Mac app and verified its new Screen time setup page.
- The user enabled sharing and granted Usage access manually, then synced.
- The live Mac archive received one phone, seven unique local-day summaries,
  allowed status, hourly totals matching the device totals, and app summaries.
  Detailed app names/usage values are private and are not copied into this document.
- A repeat/background-job check was initiated; its outcome is recorded below.
- Native capture became unavailable during the populated-dashboard check. The
  persisted live archive and validation were verified directly; do not describe
  the populated UI as screenshot-verified.

## Repeat/background result

The first forced job did not send a newer screen-time snapshot because the user
had initially enabled only sharing. The user then enabled the separate screen-time
background option. A forced execution of the already-scheduled job successfully
advanced the Mac's snapshot timestamp, retaining exactly seven unique day records
and allowed status. This verifies the background JobService → usage collector →
paired encrypted network → Mac validation/storage path on the real phone.
Android controls subsequent periodic timing; the debug force command did not
change grants, pairing or the selected schedule.
