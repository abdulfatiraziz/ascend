# Body maintenance estimates — QA

The maintenance card is an additive change after the Body/artwork branch commit.
No tracker/watch/phone message format changes are required. Height, the formula
coefficient and optional full-day marks live in training.json. Optional Codable
fields allow older training archives to decode; corrupt-file preservation stays
in place. Personal spec values were not put into source, fixtures or images.

## Calculation decisions

The spec's sign was corrected: TDEE = intake − (end weight − start weight) ×
7,700 / elapsed days, so loss implies expenditure above intake. First/last
seven-day weight averages are separated by their observation centroids, not by
the nominal whole-window duration. This avoids halving the inferred weight rate
in a densely observed 14-day window. Daily averaging stops multiple weigh-ins
on one date from disproportionately weighting that end.

Only closed local days and confirmed meals are counted. Confirmed values fall
back to their saved estimate when kcal is absent. Missing days stay unknown and
are excluded from the full-day intake average. The gate is 12/14 or 24/28 full
days, four weigh-ins, and at least two distinct dates in each end block. A user
may explicitly mark a low-meal/low-kcal date complete after review. The 1,200
logging threshold is not an intake prescription. Watch active calories are
labelled as active-only and never used for planning targets. Current Bridge
has no total-daily-energy record, so the UI does not fabricate a device TDEE.

Mifflin–St Jeor uses the simplified original equation:
https://pubmed.ncbi.nlm.nih.gov/2305711/
The activity bins and 7,700 kcal/kg conversion are stated heuristics; the card
warns about water shifts and adaptation rather than claiming laboratory accuracy.
A dynamic reference model is https://www.niddk.nih.gov/bwp .

## Validation

213 checks passed including the 10 new maintenance groups and existing Android
encrypted-link interoperability. The Android screen-time math suite also passed.
New tests cover male/female formula coefficients, adults only, loss/gain signs,
missing meal days, 14/28-day gates, explicit complete marks, four clustered
weigh-ins, current/unconfirmed meal exclusion, estimated-kcal fallback, unknown
activity, multiplier bins, watch-independent targets, aggressive deadlines,
rounding, optional-field backward decoding and calendar-key validation.
Native debug and final release builds succeeded. The actual sample app exposed
both window choices and all three estimates in its accessibility tree. A native
NSHostingView sample export was inspected, caught the picker-label/stacked-tile
layout issue, and verified its correction to a compact selector and three columns.
The final generated-data render is ignored build/evidence/body-native-sample.png
and was shown in chat before this change's commit. Export is opt-in behind
ASCEND_BODY_SAMPLE, ASCEND_DATA_DIR and ASCEND_QA_CAPTURE_DIR and renders only the
app's own supplied sample view; it does not read the display or other apps.
Computer-use action sessions remained unreliable after restart, so the final
28-day selector and completion toggle were fixture-tested rather than clicked.
No actual photos, personal plan values or live archive data were used in QA.
