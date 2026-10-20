# Patterns, caffeine and daily reflections

Open **Patterns** in Ascend. This first set adds sleep timing, caffeine and overall
energy, with optional mood/stress context. Everything runs locally. It uses your
existing Mi Fitness sleep/workout records and generic urge logs where available.
No additional phone permission or AI connection is required.

## Daily story

Select a past date or today. The summary shows the main sleep window, logged
caffeine and overall energy. The timeline combines overnight sleep, caffeine,
urge entries and imported workouts. Sleep is assigned to its wake date.
Click a caffeine/urge row to edit it; click a sleep row to review/correct the window.

**Daily check-in** lets you rate energy from 1–5. Mood and stress are optional;
expand their section. Notes are optional and excluded from automatic AI context.
Skip means unknown, not a zero rating. Ratings describe your overall day.

If the watch hasn't shared a night, enable **Use a manual sleep window** and enter
bedtime and wake time. Wake time must be on the selected date and in the past or
present. Optional asleep hours must fit inside the window. Windows can cross
midnight and account for elapsed time across daylight-saving changes.

A manual window takes priority over watch sleep for that date. Turn it off to
return to the watch's main session. Original watch records stay intact. Where
there are several watch sessions, the longest eligible session is used for this
overnight comparison; naps are not added to it. A sleep window can include awake
time and is kept distinct from reported/manual asleep duration.

**Log caffeine** saves its name, time and optional amount in mg. Unknown amounts
stay unknown. Values from labels or your own estimates may be entered; no default
dose is fabricated. Edit an entry from the timeline. Historical entries can be
moved to another date through their date/time field. Future entries are blocked.

At the end of a date, use the daily check-in to mark **Caffeine log complete**
and/or **Urge log complete**. Do this for confirmed zero days too. These markers
separate a finished zero from a day that wasn't logged. You can still correct
entries after marking complete.

The quick menu in the menu bar panel also opens Daily check-in, Log caffeine and
Patterns. Quick-menu entries always target today.

## Trends and comparisons

Choose **Trends & patterns** and 14, 28 or 84 completed dates. The window ends
yesterday. Today's daily story updates immediately, while today stays out of
comparisons and these completed-date charts.

Charts show sleep-window duration, energy and complete caffeine totals. Points
show recorded dates without filling gaps. Coverage counts remain visible.
Bedtime variation is the average circular clock difference around your usual
bedtime, so 23:50 and 00:10 are close rather than twelve hours apart.

Four exploratory comparisons are available:

- Sleep window and next-day energy.
- Sleep window and urges on the wake date, using only complete urge logs.
- Caffeine in the six hours before bedtime and that night's sleep window.
- Sleep window and closed-day habit completion within the current cycle.

A comparison needs **14 paired dates and at least five in each group** before
showing averages. Before that it shows progress and group sizes. These thresholds
are a product rule for limiting sparse comparisons, not a statistical guarantee.
The app describes associations without asserting causes or offering diagnoses.

Sleep groups use under 7h versus 7h+ window length. The caffeine comparison uses a
six-hour window before the actual bedtime. These are analytical groupings, not
personalized health recommendations. For a caffeine window crossing midnight,
every local date it touches must have a completed caffeine log. Entries with an
unknown dose count for timing; explicit 0 mg entries do not. A daily dose chart
needs a complete log and known amounts for every entry; a confirmed empty log is 0.

Habit comparisons follow the existing scoring rules: unlogged scheduled habits
count as missed; rest dates and dates without scheduled habits are excluded.
Other factors can differ between comparison groups, so the displayed differences
should be treated as questions to explore.

## Saving, privacy and compatibility

Saving a reflection or caffeine entry offers session Undo. Deleting one requires
confirmation, creates a dated backup and offers Undo. Empty reflections remove
the observation; other records are preserved. An unchanged save preserves Undo.
Undo lasts until the next successful edit or app quit.

These records never complete/uncomplete habits automatically. Habit resets and
cycle restart preserve the journal. Tracker JSON export/restore includes it.
Automatic Claude context excludes the whole journal, notes and caffeine names.
An AI proposal waiting while you edit this data becomes stale and cannot overwrite it.

New saves use tracker schema 3. Existing schema 1 and 2 backups load with an empty
journal and preserve their other records. Use the current app to edit the new format.
Nutrition imports, weight/waist tracking, hourly steps and optional HRV/resting-heart-
rate imports are outside this first set.
