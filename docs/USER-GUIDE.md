# Ascend user guide

Ascend is a personal macOS tracker. Your plan, check-ins, routine and urge logs
are stored on your Mac. Your portrait avatar is a cosmetic reflection of check-ins.

## Daily use

- **Today:** check/uncheck habits or log a numeric value. Remaining hides completed
  items; All lets you review and reopen them.
- **Calendar:** select any date to correct its check-ins. Future dates show the
  schedule without allowing completion. Earlier dates retain their original rules.
- **Goals:** edit goal dates and habit recurrence. Schedule/target/time changes
  apply from the edit date. Archived habits remain in past reviews.
- **Cycle:** review consistency across closed days. Today remains open until midnight
  in the stored calendar time zone (initially your Mac’s time zone).

## Your avatar

The supplied portraits evolve **Obsidian → Titanium → Ascendant**. In Settings,
**Avatar appearance → Follow progress** uses earned check-ins toward the cycle's
consistency goal: Titanium at halfway, Ascendant when that goal is earned.
Time alone does not advance the avatar. Fixed appearances remain available.

Select a stage below the portrait to preview it. **Live form** returns to your
current appearance; previews never write check-ins or change your score. Native
crossfades and subtle pointer tilt stop when macOS Reduce Motion is enabled.
The portrait also appears in the menu panel when Show routine clock is off.
These are image renders, with no full 3D rotation.

## Routine clock

Open **Routine → Set my routine** and choose your usual wake and bed times.
The initial clock is explicitly an example until you save your own times.

The 24-hour dial shows sleep, morning, daytime and wind-down windows. Wind-down
is calculated before bedtime, including across midnight. These windows do not
log sleep or complete habits automatically.

To put a habit on the dial, edit it and turn on **Set an exact time on the routine
clock**. Untimed habits remain in Anytime. The next-event preview skips completed
tasks and rolls into tomorrow. Rest days hide recurring timed tasks while retaining
the routine anchors and one-off tasks.

The menu bar opens a compact clock and check-in panel. Its menu can switch the
clock back to the avatar. Quick check-in in the main window shows the same panel.

## Any urge

Use **Urge** in the header, **Log an urge** in the menu panel, or **Log an urge
now** in Urges. The timestamp saves immediately. Rapid repeated taps are treated
as the same event for two seconds.

A custom label, intensity (1–5), trigger, outcome and a note are optional. Open Urges or Add details
to fill them in later. Outcomes use neutral wording: **Let it pass** or **Acted on it**. Logging an urge
never automatically changes a habit check-in.

The top of Urges counts **let pass** and **acted on** for today, the last 7 days and this cycle,
plus the days since you last acted on one. On the phone, Ascend Bridge (0.3.0+) has **Let it pass**
and **Acted on it** buttons with optional intensity, trigger and note. The urge saves on the phone
and sends straight away; if the Mac can't be reached it goes with the next sync. The phone shows the
same counts, refreshed whenever it reaches the Mac.

For a custom trigger, choose **Other · write your own** under **What was happening?**
and enter a short phrase such as “Work break” or “Late night” (up to 40 characters).
It appears in urge history, the most-logged-trigger summary and the daily timeline.
An empty field keeps the generic Other label. Switching to a preset replaces the
saved custom trigger. The separate Label field names the urge itself.

Deleting a log offers Undo until the next edit. Habit resets and restarting the
cycle preserve urge history. Urges are included in local backups and excluded
from the AI plan context.

## Patterns and daily context

Use **Patterns → Daily check-in** for overall energy, optional mood/stress, a sleep
correction and finished-log markers. Use **Log caffeine** to record a time and
optional amount. The daily timeline updates immediately. **Trends & patterns**
uses completed dates and shows averages only after sufficient paired observations.
All comparisons run locally. [Complete Patterns guide](PATTERNS.md).

## Health and watch data

Open **Health** to connect your Android phone over Wi-Fi. Use **Install phone app…**
to install or update Ascend Bridge from a QR code, then **Pair phone…** and confirm the
matching 6-digit code. After that, Ascend Bridge syncs when you open it (or tap the sync pill on
Today), and hourly in the background if you turn that on in its Settings; Ascend must
be open on the Mac and both devices on the same Wi-Fi. No
developer options are needed. [Complete setup and limitations](HEALTH-SYNC.md).

The Health tab reads as a daily report: a recovery score (resting heart rate against
your 14-day baseline 40%, time asleep against your routine's plan 40%, overnight stress
20%), vitals with small trend lines, heart rate and stress hour by hour with sleep and
workouts shaded, last night's sleep stages against your planned bedtime and wake, eight-day
trends, and a few plain-language signals. Use the arrows or date picker for earlier days.
The phone and Mi Fitness cloud connections sit under **Sources** at the bottom.

Mi Fitness passes only workout heart rate on to Health Connect. For all-day heart
rate, stress (1–100) and Mi Fitness's daily resting heart rate, click **Sign in with
Xiaomi…** under the phone panel. Ascend opens Xiaomi's sign-in page in your browser;
if the browser is already signed in to Xiaomi it's approved straight away, otherwise
sign in there and click the button again. Ascend then reads those types from your
Xiaomi account every hour (14 days the first time) while the phone keeps supplying
sleep, steps and workouts. The sign-in is kept in the Keychain; **Sign out…** forgets
it and hands heart rate back to the phone. This uses Xiaomi's unofficial app API, so a
change on Xiaomi's side can stop it until Ascend is updated.

Health data stays separate from habit scores and AI context. Importing activity
calories does not log food intake. Each sync creates a backup and offers Undo.

## Meals

Take meal photos in Ascend Bridge (camera or photo picker) with an optional note,
then Sync to Mac, or drag photos onto **Meals** on the Mac. Claude estimates each
meal's calories and macros as a range. Adjust the numbers and click **Confirm meal**;
confirmed meals set that day's Calorie target and Protein target check-ins. The
header shows the day's totals against your targets. Photo estimates are rough, often
20–30% off, mostly from oil and portion size, so notes help.

A meal can have up to 10 photos, for example a plate built up on a kitchen scale
with a photo after each food is added. On the phone, tap **Add photo** in the note
dialog after each step, or pick several photos from the gallery and choose **One
meal**; on the Mac, choose **One meal** when you add several photos. Claude reads
all the photos together, uses the scale readings (zeroed or running total) and
counts each food once. The meal is estimated once every photo has arrived; **Estimate
now** skips waiting for the rest.
No health records are invented when access or a metric is unavailable.

## Medicines

In Ascend Bridge (0.4.0+), tap **Add medicines (photos)** and photograph or pick every
side of every medicine (front, back, strip, leaflet) in any order, up to 20 photos, then
**Done**. The batch goes to the Mac, where Claude groups the photos by medicine and reads
name, active ingredients, strength, form and a general category. Photos it can't place
wait in **Not sure**; drag them onto the right card or make them a new medicine. You can
also drop photos on **Meds** on the Mac, or **Add by name**.

Check each card and add the schedule your doctor gave you: every day, certain weekdays,
every few days or as needed; 1–4 times a day; amount; before, with or after food; start
and optional end date. Or tell Ask Ascend (“Vitamin D3 1 tablet once daily after breakfast”)
and apply the preview. Claude only copies what's printed or what you say; it never sets
a dose. **Stop taking** keeps history; **Delete** removes it.

The phone lists today's doses with **Taken** buttons and reminds you at each time for the
next 14 days, with a Taken button on the notification. Taps sync to the Mac, which shows
taken vs missed for 7 days and the cycle. Taking every scheduled dose ticks your
medication habit, such as “Take medication” (never overriding a tick you made). After changing a schedule on
the Mac, tap **Sync to Mac** on the phone to refresh reminders.

Forgot to log a dose? On the Mac's Meds screen, click a day in the last-7-days strip (or use
the arrows and date picker) and tick **Taken**. A dose logged for an earlier day is saved at
its scheduled time and updates that day's medication habit.

## Notes

Keep what a chat settled. In Ask Ascend, click **Save as note** (or ••• → Save chat as note)
and Claude drafts a summary: type (Journal, Plan, Decision or Insight), title, a few bullets
and action items. Edit it and save. Right-click a single reply → **Save reply as note** to
keep just that answer. Claude may also offer a `save_note` change at the end of a planning
chat, which you review like any other edit. Write notes by hand with **New note** in Notes.

Notes lists everything newest first, pinned on top, with type filters and search; each note
links back to its chat. Turn on **Ascend can see this** (on by default for Plans and
Decisions) and later chats include that note, so Ascend can follow up on it. Only shared
notes are sent: pinned first, then the 12 most recent. Notes live in your tracker data
and backups.

## Progress photos

Photos keeps dated pictures of your **Hair**, **Hairline**, **Face** and **Body**. Click
**Add photos…** or drag photos onto the window. Ascend reads when each photo was taken from
the camera's data (or the file date), and you set the area, the angle (front, left, right,
back, top) and an optional note before adding. Click a photo later to fix its date, area,
angle or note, or to delete it (Undo is available until your next edit).

Pick an area and an angle, then a **Before** and an **After** photo (the oldest and newest
by default). View them side by side, or as an overlay with a slider that blends one into
the other. **Ask Claude to compare** sends just those two photos to Claude, which describes
what changed (better, same, worse or unclear), where, and whether light, angle or distance
differ enough to mislead. **Save as note** keeps the result as an Insight note that later
chats can see.

Comparisons are only fair from the same angle in the same light; each area shows a tip.
To talk them through with Ask Ascend, click **Ask Ascend** on the comparison (or right-click
a photo → Ask Ascend about this photo), or in the chat use **Photo ▾ → From progress photos…**.
Up to four album photos attach to your next message, each labelled with its area, angle and
date. Ask Ascend otherwise knows only which areas, angles and dates your album has, so if
you ask it to look without attaching, it tells you which photos to attach.

Copies are stored up to 2048 px in `Progress/` beside tracker.json, with location and camera
data removed. Images reach Claude only when you compare or attach them. The phone app
doesn't take progress photos.

## Ask Ascend (Claude)

Ask Ascend uses Claude Code with your personal account, the same as `claude --personal`.

1. Sign in once: run `claude --personal` in Terminal if you haven't already.
2. Open **Chat** in the sidebar (or press **⌘J** / **Ask Ascend**). **Claude settings**, at the
   bottom of the chat list, shows the detected
   Claude Code path, the profile folder (`~/.claude-personal`), the model for new chats
   and whether to share recent check-ins. **Send test message** confirms it works.
3. Chat normally: ask how your cycle is going, talk through a setback, or plan a week.
4. Ask for a change and Claude prepares it. Review the before/after preview and choose
   Apply changes.

Chats:

- Chat is a full screen: saved chats on the left (grouped by Today, Previous 7 days, Previous
  30 days and Older, with search), the conversation in the middle and the message box at the
  bottom. **New chat** (⌘N) starts one; the sidebar icon hides the list. Right-click a chat
  to rename or delete it. Each reply has Copy and Save-as-note buttons.
- The model menu at the top (Opus 5.5, Sonnet 5.5, Haiku 5.5, Fable 5.1) applies to the open chat and
  can be changed mid-conversation. Fable 5.1 may need usage credits on your plan.
- The effort menu (Low, Medium, High, Extra high, Max) sits beside it and also applies
  per chat. Every model defaults to Medium; higher effort thinks longer and uses more of
  your plan. Claude settings sets the effort for new chats.
- **+** in the message box attaches up to four photos per message: choose files, paste from
  the clipboard (for example a ⌃⇧⌘4 screenshot), pick from your progress photos, or drag
  them onto the chat. The lock icon shows exactly what is sent to Claude. A message can be photos
  only. Photos stay in the chat as thumbnails (click to open), Claude can refer back to them
  later in the same chat, and deleting the chat deletes them. Large photos are resized and
  location data is removed before anything is saved or sent.
- **Copy Terminal command** in a chat's ⋯ menu copies
  `cd … && claude --personal --resume <id>` to continue that conversation in Terminal.
- **Stop** cancels a reply. Errors from Claude (sign-in, limits, unavailable model) are
  shown in the chat with a retry button.

Example requests:

- “How did the last week go? What should I focus on?”
- (With a photo of a meal) “Roughly how much protein is this?”
- “Add a note to Take medication: after breakfast.”
- “Log 7.5 hours of sleep today.”
- “Move my Monday gym session to Tuesday and keep the other days.”
- “Create a reading goal with a daily 20-minute reading habit.”
- “Set wake time to 08:00, bedtime to midnight, and wind-down to two hours.”
- “Start a new 90-day cycle today.”

Ascend validates the entire proposal before saving. A bad operation rejects the
whole proposal. Changing the plan or date while a proposal is open makes it stale;
send the request again to generate a fresh preview. Destructive changes receive an
additional confirmation. Every applied proposal creates a dated backup and Undo.
The chat also offers Undo after an AI edit.

Each message sends your text plus your goals, habits, schedules, targets, routine windows
and current cycle to Anthropic through Claude Code. With **Share recent check-ins, progress
and habit notes** on (the default), it also sends cycle progress, the last 14 days of
check-ins and rest days, and habit notes. Urge records, health records and the wellbeing
journal are never sent. Photos are sent only with the message you attach them to.
Claude Code keeps earlier turns of the chat, including photos, in its session.

Nothing is sent until you send a message. Usage counts toward your Claude plan.
The other app features remain available offline.

## Resets and recovery

- **Day options → Rest day:** excludes recurring tasks from consistency while
  preserving their logged values. Resume the day before editing those tasks.
- **Reset this date:** clears only that date’s habit check-ins, numbers and rest marker.
- **Settings → Start a new cycle:** starts today, clears today’s habit check-ins,
  moves all goal windows and active one-off due dates, and retains earlier records.
- **Reset all check-in history:** clears habit check-ins and rest markers while
  keeping goals, habits, routine settings and urge logs.

Resets/restarts create dated backups. Undo lasts until the next successful edit or until you quit Ascend.
An unchanged save does not consume Undo. If a disk write fails, the in-memory change
is rolled back, the error is shown, and Settings provides Retry saving.

Data lives at `~/Library/Application Support/Ascend/tracker.json`. The previous
valid file is `tracker.json.backup`; resets and AI changes create additional dated
JSON backups. Export/restore and Show data are in Settings. An unreadable file is
preserved, and a valid backup is recovered when available.

## Shortcuts

- **⌘⇧K:** Quick check-in
- **⌘J:** Open the Chat screen
- **⌘N:** New chat (on the Chat screen)
- **⌘⇧U:** Log an urge while Ascend is active
- **⌘Return:** Send a chat message
- **⌘⇧E:** Export backup

The app is locally ad-hoc signed. Keep using `build/Ascend.app`; no account,
notarized installer or background server is required for local tracking.

## Body: goals, training and steps

Open **Body** in the sidebar. Health retains a one-line weight/scale-fat summary
that opens this screen. Your existing Dr Trust readings and connection settings
are under **Scale readings & Dr Trust connection**.

- **Goal & coach settings:** set body-fat percentage, an optional weight and date,
  editable checkpoints, age for estimated heart-rate zones, and the start of Week 1.
  Lean mass uses the latest weight and latest available scale-fat estimate. Weight
  at goal assumes lean mass is retained. Pace is a regression over trailing weekly
  averages; sparse or stale readings do not create a confident projection. A deadline
  requiring over 1% loss per week shows a warning and a 0.5–0.75% planning range.
- **Log weight:** enter kg and a date/time. Manual records can be edited or deleted
  in Reading history; scale records are read only. Existing manual entries survive
  cloud sync. Dates include explicit 12-hour times in reading lists and log editors.
- **Edit weekly plan:** choose each weekday and session type. Create exercises in
  the library, tag their muscles, set equipment, sets, rep range, starting weight,
  assisted/compound flags, explicit priority-muscle tags and timed holds, then add
  and order them in a session. Pair adjacent exercises with the superset toggle. Cardio has type,
  minutes, incline and speed. Suggestions do not change the plan automatically.
- **Today:** see previous sets and the next progression hint. Log hard sets or
  warm-ups with optional RPE; Tab moves through fields and Command–Return saves.
  Same as last copies the previous set pattern. Mark the session done, rested or
  skipped. History shows session volume, best sets, estimated Epley 1RM and PRs;
  assisted exercises use lower assistance as progress, without a misleading 1RM.
- **Steps today:** the daily floor defaults to 7,000; the higher target comes from
  your existing steps habit. No duplicate habit is created. Editable blocks cover
  base movement, morning sunlight, gym days, treadmill days and rest days. Watch
  step bursts in a matching window or a matching workout can tick a block; other
  boxes are manual. Planned estimates are never added to actual steps. A low-count
  treadmill workout can show the wrist/rails hint. Unknown steps remain unknown.
- **Coach rules:** toggle reminders, priority-muscle volume warnings, progression/stall flags,
  late hard-session flags, calorie notes and the walking-pad rule. Thresholds,
  times, step blocks and the treadmill hint are editable. A recent meal timestamp
  gives the walking nudge a within-30-minutes option; morning blocks use Routine's
  wake time. Easy evening walks are allowed. Calories never drive eat-back advice.
- **Weekly scorecard:** strength /3, cardio /3, floor-step days /7 and one 45–75 min
  low-intensity session. Watch and manual completions on a day count once. Workouts
  match the same day's plan, show heart rate, distance and calories when available,
  and link late hard sessions to Routine's bedtime. A planned flat walking-pad
  session with low or unknown HR counts as walking only. The watch type alone does
  not prove incline; intensity is an age-based estimate, not a measured fitness zone.
- **Muscle map:** front/back colors show logged hard sets only (0 neutral, 1–9 dim,
  10–20 accent, 21+ warning). Hover, tap or use the region picker for sets and the
  exercises that contributed. This is not a regional fat or body-composition map.
- **Progress photos:** view latest Body photos and open the existing same-angle
  first/latest comparison. Images are not sent automatically to chat.

Training lives in a separate versioned `training.json` alongside the tracker.
Writes are atomic and corrupt/unsupported files are preserved with an error;
there are no per-save training backups. Copy this file and the separate body
backup when making a full manual backup. Main tracker export does not include it.
Ask Ascend receives a short Body goal, pace, weekly scorecard, today's session
and recent-lifts summary when sending a chat. No Body file paths or photo data
are added to that summary. Android gym logging is not part of this release.

### Workout artwork

Body → **Workout artwork** opens six AI-generated transparent exercise
illustrations. Choose an illustration in the exercise editor to attach it to a
movement. The optional **Subtle GIF motion** toggle gently floats the picture;
it does not demonstrate a repetition or assess form. Static PNG is the default.
The old two/three-pose GymMane animations have been removed.

Bridge 0.8.1 adds **Workout artwork · offline** on Today, using the same bundled
images/GIFs without new permissions or sign-in. Android has a read-only artwork
library; personal training-plan/set-log sync remains a future feature. Generated
art uses fictional subjects and no personal photos, measurements or private
weights. The six movements are incline dumbbell press, chest-supported row,
leg press, lateral raise, assisted pull-up and plank.

Priority volume warnings replace exercise-specific Saturday suggestions. Use
explicit priority tags for upper chest, side delts, upper back, rear delts, quads
and hamstrings. Warnings distinguish planned weekly sets from hard sets logged
so far; they do not automatically alter your plan. The minimum and priority list
are editable. The plan editor supports adjacent exercise supersets and rest
intervals; timed holds use seconds and do not display an estimated 1RM.
