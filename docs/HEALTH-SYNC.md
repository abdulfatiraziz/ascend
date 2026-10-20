# Phone sync over Wi-Fi

Ascend can import the data Mi Fitness writes to Android Health Connect, plus meal
photos you take on the phone. The path is watch → Mi Fitness → Health Connect →
Ascend Bridge → your Wi-Fi → Ascend on Mac. Developer options and USB debugging are
not needed; Bridge 0.2 replaced the earlier Android-debugging transfer.
Only the Mi Fitness source (`com.xiaomi.wearable`) is queried. Source device
metadata may be absent, so the Mac labels this data Mi Fitness rather than
assuming every record was measured by a particular watch model.

## Setup

1. Sync your watch in Mi Fitness and enable its Health Connect sharing.
2. Keep the phone and Mac on the same Wi-Fi, with Ascend open on the Mac. The first
   time, macOS may ask to let Ascend use the local network; allow it.
3. Install or update Ascend Bridge: on the Mac open **Health → Install phone app…**,
   point the Pixel camera at the QR code, download the APK and allow your browser to
   install it. An update keeps the phone's existing Health Connect permissions.
4. In Ascend Bridge tap **Choose health permissions** and select only the read access
   you want. Ascend cannot approve this on your behalf.
5. On the Mac click **Pair phone…**. In Ascend Bridge tap **Pair with Mac**. Check
   that both screens show the same 6-digit code, then click **Codes match · Pair** on
   the Mac. Pairing happens once.
6. Open Ascend Bridge: it syncs quietly when it opens (at most every 10 minutes),
   or tap the "Synced … ago" pill on Today. Health data and anything queued (meal
   and medicine photos, urges, doses) are sent together, and the Mac replies with
   today's progress, urge counts and upcoming doses.
7. Optional: Settings → **Sync in the background** asks Health Connect for
   "Access data in the background". Bridge then syncs about once an hour on Wi-Fi,
   only when your paired Mac is found, so your night's sleep is on the Mac before
   you open the phone.

If the phone says no Mac was found, check that Ascend is open, both devices are on
the same network (not a guest network that isolates devices), and that Ascend has
Local Network access in System Settings → Privacy & Security.

The phone permissions have now been granted and the first real import succeeded:
13 Mi Fitness records (10 heart-rate samples, two oxygen readings and one activity-
energy interval), with no Health Connect errors. No steps, sleep, distance, speed,
elevation or workout records were returned in that query. The source records had
no device model label, so their individual watch model cannot be verified from metadata.
Mi Fitness 3.59.1i on the connected Pixel has write permission for the supported
types; permissions do not guarantee records exist for every measurement.

In the subsequent 0.4.1 investigation, Mi Fitness had published steps. A source
activity-energy interval extended beyond the snapshot time and caused the strict
Mac validator to reject an otherwise useful transfer. Bridge 0.1.2 now marks that
type incomplete, preserving its earlier Mac values while valid types refresh.
The verified transfer brought in 50 steps, 68 heart-rate samples and 14 oxygen
readings. Those reflect the data shared to Health Connect, which may lag the
totals visible within Mi Fitness. See [QA 0.4.1](QA-0.4.1.md).

## What is supported

| Metric | Display |
| --- | --- |
| Heart rate | Recorded samples, sample average, observed range and dots over time |
| Steps | Health Connect daily aggregate filtered to Mi Fitness |
| Sleep | Main night with deep, light, REM and awake time plus a cycle chart (Bridge 0.2.1+); overlapping copies of one night count once; naps listed separately; session windows labeled when no stages exist |
| Blood oxygen | Recorded sample average |
| Distance | Recorded interval distance |
| Activity energy | Activity kcal, separate from dietary calories |
| Speed | Recorded sample average |
| Elevation | Recorded interval elevation gained |
| Workouts | Recorded session minutes |

Each sync asks for the past 14 calendar days in the phone’s time zone. Earlier
imported records remain on the Mac. Repeated sync replaces the refreshed window
for successfully read types and matches stable record IDs, so corrections and
source deletions within that window are reflected without duplicates. Changes
older than that window are not automatically reconciled. Denied/failed types keep
previous local records and show their status. Revoking a phone permission does
not erase earlier Mac copies or backups.

Interval records use their start date; sleep uses its end date. Sleep windows
can include awake time when stages are unavailable. Missing data displays a dash.
The app does not infer resting heart rate, diagnose health conditions, fill gaps,
or automatically mark habits complete. This is historical sync, not a continuous
heart-rate stream. Watch settings, wear time and Mi Fitness sharing determine
what is available. It cannot retrieve unsupported measurements such as ECG just
because a permission exists.

## Privacy and storage

The companion has no health write permission and no account. Foreground health reads
require its screen to be focused and the phone unlocked; during a sync it keeps the
screen on, then releases that flag. Background reads happen only if you turn on
background sync and grant Health Connect's background permission; the hourly job runs
on unmetered Wi-Fi and looks for your Mac before reading anything. It has the network permission only
to reach the Mac: it finds Ascend with DNS-SD (`_ascend-sync._tcp`) and its client
refuses any address that isn't on the local network. No cloud service, rooting or
Mi Fitness database bypass is used, and the app is no longer a debuggable build.

Pairing uses X25519 key agreement. Both devices derive a 6-digit code from the two
public keys, and the Mac stores the phone's key only after you confirm that the codes
match, which stops another device on the network from sitting in the middle. Every
later request is encrypted with AES-256-GCM using an HKDF-SHA256 key that only the
two devices hold (the Mac keeps it in the Keychain). Requests carry a fresh ID and
timestamp; replays, requests more than 10 minutes off the Mac's clock and unpaired
phones are refused. The Mac accepts connections only from private, link-local or
loopback addresses. Ascend listens only while it's open; **Forget** removes a phone.
`scripts/check-phone-link.sh` runs the Android crypto and network code on the JDK
against the real Mac server.

New tracker saves use schema 3; schema 1/2 backups are migrated when loaded.
Keep the current app when editing these backups so new fields are preserved.

The phone keeps no copy of the health export after sending it. Meal photos wait in
its private storage and are deleted only after the Mac accepts each one. Mac health
records are stored in the tracker JSON and its local backups. Every import makes a
dated safety backup and offers Undo until the next successful edit or app quit.
Export/restore includes health data. Health records are excluded from Claude's
automatic context, as are urge logs.

## Meal photos

In Ascend Bridge, **Take meal photo** opens the system camera and **Choose meal
photos** opens the system photo picker, so the app needs no camera or storage
permission. Add an optional note such as "2 rotis, dal, cooked in ghee". The phone
resizes each photo to at most 1568 px, turns it upright and re-encodes it, which
removes EXIF and location data. On the Mac, each meal appears in **Meals**, where
Claude estimates calories, protein, carbs and fat as a range with a confidence level.
Review and adjust the numbers, then **Confirm meal**. Confirmed meals set that day's
Calorie target and Protein target check-ins to the day's totals; removing every
confirmed meal clears only values that meals wrote, never a number you typed.

Local limits are 25 MB / 100,000 records per phone snapshot and 500,000 records in
the Mac archive. An invalid/oversized import is rejected without overwriting data.
The app displays connection/permission errors and retains the previous snapshot.
A locked or background phone can prevent reading other apps' Health Connect data.

## Missing steps

The Steps card distinguishes absent Mi Fitness data from zero. Use its **?**
button for permission, refresh-error and selected-date guidance. Steps visible
inside Mi Fitness must also be written to Health Connect. In Android Health
Connect, browse Steps entries and confirm Mi Fitness is the source, then keep
Ascend Bridge visible and sync from the Mac. The notification shade can cover
the bridge and pause reads even while its activity is open.

The companion checks source-filtered raw step record counts before fetching
daily aggregates. Its local export includes diagnostic counts; raw intervals
are never added to the aggregates. If raw entries exist but no daily totals are
returned, the snapshot reports a steps error so prior Mac steps are retained.
It does not silently include phone-only steps or other apps. Android documents
data-origin filters and activity deduplication in its
[aggregation guide](https://developer.android.com/health-and-fitness/health-connect/aggregate-data).

For raw interval types, a record ending after the snapshot time flags that type
as incomplete. The bridge does not invent a proportional value by clipping it.
Sample series keep only samples inside the requested time window, preserving
their original stable sample-index IDs. Mac nonce, freshness, permission, value
and timestamp validation remain strict.

## Build and provenance

- Android source: `android/bridge/`; no third-party app runtime dependencies.
- Build: `scripts/build-android-bridge.sh`, using the JDK/Android SDK under `build/tools`.
- APK: `build/android/AscendBridge.apk`, signed with a project-local development key.
  Keep `build/android/local-signing.p12` to sign compatible future updates.
- The Mac bundle includes the APK for Wi-Fi download; it no longer bundles ADB.
  `build/` is excluded from Git.
- Bridge 0.1.x was installed with REA 6.5.0 over Android debugging. Evidence is under
  `build/health-research/`.
- Official references: [REA ADB guide](https://github.com/morluto/rea/blob/main/docs/adb-device-analysis.md),
  [Android Health Connect reads](https://developer.android.com/health-and-fitness/health-connect/read-data),
  [Android platform tools](https://developer.android.com/tools/releases/platform-tools).

The acquired Mi Fitness APK and its evidence are research artifacts, not bundled
in Ascend or executed on the Mac. Android's private Mi Fitness database was
inaccessible to normal debugging; that boundary was preserved.
