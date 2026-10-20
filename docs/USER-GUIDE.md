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

Health data stays separate from habit scores and AI context. Importing activity
calories does not log food intake. Each sync creates a backup and offers Undo.

## Meals

Take meal photos in Ascend Bridge (camera or photo picker) with an optional note,
then Sync to Mac, or drag photos onto **Meals** on the Mac. Claude estimates each
meal's calories and macros as a range. Adjust the numbers and click **Confirm meal**;
confirmed meals set that day's Calorie target and Protein target check-ins. The
header shows the day's totals against your targets. Photo estimates are rough, often
20–30% off, mostly from oil and portion size, so notes help.
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
and optional end date. Or tell Ask Ascend (“Finasteride 1 mg once daily after breakfast”)
and apply the preview. Claude only copies what's printed or what you say; it never sets
a dose. **Stop taking** keeps history; **Delete** removes it.

The phone lists today's doses with **Taken** buttons and reminds you at each time for the
next 14 days, with a Taken button on the notification. Taps sync to the Mac, which shows
taken vs missed for 7 days and the cycle. Taking every scheduled dose ticks your
medication habit, such as “Take medication” (never overriding a tick you made). After changing a schedule on
the Mac, tap **Sync to Mac** on the phone to refresh reminders.

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
2. Press **⌘J** (or **Ask Ascend**). Claude settings (gear icon) shows the detected
   Claude Code path, the profile folder (`~/.claude-personal`), the model for new chats
   and whether to share recent check-ins. **Send test message** confirms it works.
3. Chat normally: ask how your cycle is going, talk through a setback, or plan a week.
4. Ask for a change and Claude prepares it. Review the before/after preview and choose
   Apply changes.

Chats:

- The clock icon lists saved chats; the pencil icon starts a new one. Right-click a chat
  to rename or delete it.
- The model menu (Opus 5.5, Sonnet 5.5, Haiku 5.5, Fable 5.1) applies to the open chat and
  can be changed mid-conversation. Fable 5.1 may need usage credits on your plan.
- The effort menu (Low, Medium, High, Extra high, Max) sits beside it and also applies
  per chat. Every model defaults to Medium; higher effort thinks longer and uses more of
  your plan. Claude settings sets the effort for new chats.
- **Photo** attaches up to four photos per message: choose files, paste from the clipboard
  (for example a ⌃⇧⌘4 screenshot), or drag them onto the drawer. A message can be photos
  only. Photos stay in the chat as thumbnails (click to open), Claude can refer back to them
  later in the same chat, and deleting the chat deletes them. Large photos are resized and
  location data is removed before anything is saved or sent.
- **Copy Terminal command** in a chat's ⋯ menu copies
  `cd … && claude --personal --resume <id>` to continue that conversation in Terminal.
- **Stop** cancels a reply. Errors from Claude (sign-in, limits, unavailable model) are
  shown in the drawer with a retry button.

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
The drawer also exposes Undo after an AI edit.

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
- **⌘J:** Open/close Ask Ascend
- **⌘⇧U:** Log an urge while Ascend is active
- **⌘Return:** Send from the AI drawer
- **⌘⇧E:** Export backup

The app is locally ad-hoc signed. Keep using `build/Ascend.app`; no account,
notarized installer or background server is required for local tracking.
