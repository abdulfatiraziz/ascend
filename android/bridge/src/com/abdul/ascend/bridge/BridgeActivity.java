package com.abdul.ascend.bridge;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.app.NotificationManager;
import android.content.ClipData;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.PermissionInfo;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.provider.MediaStore;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.PublicKey;
import java.time.*;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/**
 * Ascend on the phone: today at a glance, meal and medicine photos, doses with reminders, and urges, all sent to
 * Ascend on your Mac over the same Wi-Fi, encrypted with a key from one-time pairing. It reads the Mi Fitness data
 * you allow in Health Connect and never writes health data. No account, cloud service or Android debugging.
 */
public final class BridgeActivity extends Activity {
    enum Screen { TODAY, MEALS, MEDS, URGES, SETTINGS, ADD_MEDS }
    static final String LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK";
    static final int REQ_HEALTH = 7, REQ_NETWORK = 8, REQ_CAMERA = 11, REQ_PICK = 12, REQ_NOTIFY = 13, REQ_BACKGROUND = 14;
    static final String[] TRIGGERS = {"Stress", "Coffee", "After a meal", "Social", "Boredom"};
    static final String VERSION = "0.6.2";

    SyncEngine engine;
    Ui ui;
    SharedPreferences prefs;
    final ExecutorService network = Executors.newSingleThreadExecutor();
    final Handler main = new Handler(android.os.Looper.getMainLooper());
    final Map<String, Bitmap> thumbs = new HashMap<>();
    FrameLayout root, content;
    View statusScrim;
    LinearLayout nav;
    TextView toast;
    Screen screen = Screen.TODAY;
    int insetTop, insetBottom;
    boolean syncing;
    String captureName;
    /** "meal" or "med": where the next camera or picker result goes. */
    String photoMode = "meal";
    Runnable afterNetwork, networkDenied;
    volatile boolean pairingCancelled;

    // MARK: Lifecycle
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        engine = new SyncEngine(this); ui = new Ui(this); prefs = engine.prefs;
        if (state != null) {
            captureName = state.getString("captureName"); photoMode = state.getString("photoMode", "meal");
            try { screen = Screen.valueOf(state.getString("screen", "TODAY")); } catch (Exception ignored) {}
        }
        Window w = getWindow();
        w.setDecorFitsSystemWindows(false);
        w.setStatusBarColor(Color.TRANSPARENT); w.setNavigationBarColor(Color.TRANSPARENT);
        root = new FrameLayout(this); root.setBackgroundColor(Ui.BG);
        content = new FrameLayout(this);
        root.addView(content, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        // A solid strip behind the status bar so scrolled content doesn't run under the clock.
        statusScrim = new View(this); statusScrim.setBackgroundColor(Ui.BG);
        root.addView(statusScrim, new FrameLayout.LayoutParams(Ui.MATCH, 0, Gravity.TOP));
        nav = new LinearLayout(this);
        root.addView(nav, new FrameLayout.LayoutParams(Ui.MATCH, Ui.WRAP, Gravity.BOTTOM));
        toast = ui.text("", 13, Ui.TEXT, 500);
        toast.setBackground(ui.round(Ui.PANEL2, 14, 0x24FFFFFF, 1)); ui.pad(toast, 16, 12, 16, 12); toast.setVisibility(View.GONE);
        FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(Ui.MATCH, Ui.WRAP, Gravity.BOTTOM);
        tp.setMargins(ui.dp(16), 0, ui.dp(16), 0);
        root.addView(toast, tp);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            if (bars.top != insetTop || bars.bottom != insetBottom) { insetTop = bars.top; insetBottom = bars.bottom; render(); }
            return WindowInsets.CONSUMED;
        });
        setContentView(root);
        boolean background = prefs.getBoolean("backgroundSync", false);
        SyncJob.schedule(this, background && engine.backgroundAllowed());
        render();
    }
    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putString("captureName", captureName); out.putString("photoMode", photoMode); out.putString("screen", screen.name());
    }
    @Override protected void onResume() { super.onResume(); render(); }
    /** Quietly syncs when the app comes to the front, at most every 10 minutes. */
    @Override public void onWindowFocusChanged(boolean focus) {
        super.onWindowFocusChanged(focus);
        if (focus && prefs.getBoolean("autoSync", true) && engine.paired() && !syncing
            && System.currentTimeMillis() - prefs.getLong("lastSync", 0) > 10 * 60 * 1000L) sync(true, true);
    }
    /**
     * Back returns to the previous screen and only leaves the app from Today. With predictive back (target SDK 36),
     * onBackPressed isn't called, so a callback is registered while any other screen is showing.
     */
    final android.window.OnBackInvokedCallback back = () -> show(screen == Screen.ADD_MEDS ? Screen.MEDS : Screen.TODAY);
    boolean backRegistered;
    void updateBack() {
        boolean want = screen != Screen.TODAY;
        if (want == backRegistered) return;
        android.window.OnBackInvokedDispatcher dispatcher = getOnBackInvokedDispatcher();
        if (want) dispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, back);
        else dispatcher.unregisterOnBackInvokedCallback(back);
        backRegistered = want;
    }
    @Override protected void onDestroy() { super.onDestroy(); network.shutdown(); }

    void show(Screen s) { screen = s; render(); }
    void render() {
        if (root == null) return;
        content.removeAllViews();
        View page;
        switch (screen) {
            case MEALS: page = meals(); break;
            case MEDS: page = meds(); break;
            case URGES: page = urges(); break;
            case SETTINGS: page = settings(); break;
            case ADD_MEDS: page = addMeds(); break;
            default: page = today();
        }
        content.addView(page, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        boolean tabs = screen != Screen.SETTINGS && screen != Screen.ADD_MEDS;
        nav.setVisibility(tabs ? View.VISIBLE : View.GONE);
        if (tabs) buildNav();
        ((FrameLayout.LayoutParams) toast.getLayoutParams()).bottomMargin = (tabs ? ui.dp(84) : ui.dp(96)) + insetBottom + ui.dp(8);
        statusScrim.getLayoutParams().height = insetTop; statusScrim.requestLayout();
        updateBack();
    }
    void toast(String message) {
        if (message == null || message.isEmpty()) return;
        String text = String.join(" · ", message.trim().split("\n"));
        toast.setText(text.length() > 180 ? text.substring(0, 177) + "…" : text);
        toast.setVisibility(View.VISIBLE); toast.bringToFront();
        main.removeCallbacksAndMessages("toast");
        main.postAtTime(() -> toast.setVisibility(View.GONE), "toast", android.os.SystemClock.uptimeMillis() + 4500);
    }
    void runUi(Runnable r) { runOnUiThread(r); }

    // MARK: Layout pieces
    /** A scrolling page with the system bars and tab bar kept clear. */
    LinearLayout page(ViewGroup[] holder, boolean tabs) {
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout col = ui.column(16);
        col.setPadding(ui.dp(20), insetTop + ui.dp(20), ui.dp(20), insetBottom + ui.dp(tabs ? 108 : 120));
        scroll.addView(col);
        holder[0] = scroll;
        return col;
    }
    View header(String kicker, String title, View trailing) {
        LinearLayout row = ui.row(12); row.setGravity(Gravity.BOTTOM);
        LinearLayout text = ui.column(4);
        text.addView(ui.oneLine(ui.kicker(kicker))); text.addView(ui.title(title));
        row.addView(text, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (trailing != null) row.addView(trailing);
        return row;
    }
    View topBar(String title, Screen back, View trailing) {
        LinearLayout row = ui.row(4);
        FrameLayout backButton = new FrameLayout(this);
        backButton.addView(ui.iconView("ic_back", Ui.TEXT, 22), new FrameLayout.LayoutParams(ui.dp(22), ui.dp(22), Gravity.CENTER));
        backButton.setContentDescription("Back"); backButton.setOnClickListener(Ui.tap(v -> show(back)));
        row.addView(backButton, new LinearLayout.LayoutParams(ui.dp(44), ui.dp(44)));
        TextView t = ui.text(title, 24, Ui.TEXT, 700); t.setLetterSpacing(-0.02f);
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (trailing != null) row.addView(trailing);
        row.setPadding(-ui.dp(10), 0, 0, 0);
        return row;
    }
    View circleButton(String icon, String label, View.OnClickListener l) {
        FrameLayout f = new FrameLayout(this);
        f.setBackground(ui.round(Ui.PANEL, 22, Ui.LINE, 1)); f.setContentDescription(label);
        f.addView(ui.iconView(icon, Ui.SOFT, 20), new FrameLayout.LayoutParams(ui.dp(20), ui.dp(20), Gravity.CENTER));
        f.setOnClickListener(Ui.tap(l));
        f.setLayoutParams(new LinearLayout.LayoutParams(ui.dp(44), ui.dp(44)));
        return f;
    }
    void buildNav() {
        nav.removeAllViews();
        nav.setOrientation(LinearLayout.HORIZONTAL);
        android.graphics.drawable.LayerDrawable navBg = new android.graphics.drawable.LayerDrawable(new android.graphics.drawable.Drawable[]{new ColorDrawable(Ui.LINE), new ColorDrawable(Ui.NAV)});
        navBg.setLayerInset(1, 0, 1, 0, 0);
        nav.setBackground(navBg);
        nav.setPadding(ui.dp(12), ui.dp(8), ui.dp(12), insetBottom + ui.dp(10));
        String[][] tabs = {{"Today", "ic_home"}, {"Meals", "ic_meal"}, {"Meds", "ic_pill"}, {"Urges", "ic_urge"}};
        Screen[] targets = {Screen.TODAY, Screen.MEALS, Screen.MEDS, Screen.URGES};
        for (int i = 0; i < tabs.length; i++) {
            boolean on = screen == targets[i];
            LinearLayout tab = ui.column(4); tab.setGravity(Gravity.CENTER_HORIZONTAL);
            FrameLayout pill = new FrameLayout(this);
            if (on) pill.setBackground(ui.round(0x2EA18AFF, 15, 0, 0));
            pill.addView(ui.iconView(tabs[i][1], on ? Ui.ACCENT : Ui.MUTED, 22), new FrameLayout.LayoutParams(ui.dp(22), ui.dp(22), Gravity.CENTER));
            tab.addView(pill, new LinearLayout.LayoutParams(ui.dp(56), ui.dp(30)));
            // Column children are full width, so the label itself must be centred under the icon.
            TextView label = ui.text(tabs[i][0], 11, on ? Ui.ACCENT : Ui.MUTED, on ? 600 : 500); label.setGravity(Gravity.CENTER);
            tab.addView(label);
            Screen target = targets[i];
            tab.setOnClickListener(Ui.tap(v -> show(target)));
            tab.setContentDescription(tabs[i][0]);
            nav.addView(tab, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        }
    }
    View metric(String label, String value, String unit, double fraction, int barColor, String goal) {
        LinearLayout col = ui.column(0);
        col.addView(ui.kicker(label));
        LinearLayout v = ui.row(4); v.setGravity(Gravity.BOTTOM); v.setPadding(0, ui.dp(6), 0, ui.dp(8));
        v.addView(ui.text(value, 22, Ui.TEXT, 700));
        if (!unit.isEmpty()) v.addView(ui.text(unit, 13, Ui.MUTED, 500));
        col.addView(v);
        if (fraction >= 0) col.addView(ui.bar(fraction, barColor));
        TextView g = ui.small(goal); g.setTextSize(11); g.setPadding(0, ui.dp(6), 0, 0);
        col.addView(g);
        return col;
    }
    /** Let pass as the headline in grey; acted on beneath it, orange only when there were any. */
    View urgeStat(String label, int passed, int acted) {
        LinearLayout col = ui.card(4); ui.pad(col, 14, 14, 14, 14);
        col.addView(ui.kicker(label));
        col.addView(ui.text(String.valueOf(passed), 20, Ui.TEXT, 700));
        col.addView(ui.text("let pass", 12, Ui.MUTED, 500));
        col.addView(ui.text(acted + " acted on", 12, acted > 0 ? Ui.ORANGE : Ui.MUTED, 500));
        return col;
    }
    View stat(String label, String value, String sub, int subColor) {
        LinearLayout col = ui.card(4); ui.pad(col, 14, 14, 14, 14);
        col.addView(ui.kicker(label));
        col.addView(ui.text(value, 20, Ui.TEXT, 700));
        TextView s = ui.text(sub, 12, subColor, 500); col.addView(s);
        return col;
    }
    static String fmt(double v) { return v == Math.rint(v) ? String.format(Locale.US, "%,d", (long) v) : String.format(Locale.US, "%.1f", v); }
    static String hhmm(int minute) { return String.format(Locale.ROOT, "%02d:%02d", minute / 60, minute % 60); }
    static String clock(long millis) {
        LocalTime t = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalTime();
        return String.format(Locale.ROOT, "%02d:%02d", t.getHour(), t.getMinute());
    }
    static String ago(long millis) {
        long min = (System.currentTimeMillis() - millis) / 60000;
        if (min < 1) return "just now";
        if (min < 60) return min + " min ago";
        if (min < 24 * 60) return (min / 60) + " h ago";
        return "on " + Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate();
    }

    // MARK: Today
    View today() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        JSONObject t = engine.today();
        String kicker = t.has("dayNumber") ? "Day " + t.optInt("dayNumber") + " of " + t.optInt("dayCount") + " · " + t.optString("cycle") : "Ascend";
        col.addView(header(kicker, "Today", circleButton("ic_gear", "Settings", v -> show(Screen.SETTINGS))));
        col.addView(syncPill(), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
        if (!engine.paired()) col.addView(setupCard());
        if (t.has("avatar")) col.addView(avatarCard(t));
        JSONObject next = nextDose();
        if (next != null) col.addView(nextDoseCard(next));
        if (t.has("habits")) col.addView(habitsCard(t));
        col.addView(ui.grid(10,
            actionTile("ic_camera", "Snap meal", v -> { photoMode = "meal"; takePhoto(); }),
            actionTile("ic_pill", "Add meds", v -> show(Screen.ADD_MEDS)),
            actionTile("ic_urge", "Log urge", v -> show(Screen.URGES))));
        if (t.length() > 0) {
            col.addView(lastNight(t));
            col.addView(daySoFar(t));
        } else if (engine.paired()) {
            col.addView(ui.small("Sync once to see your day from the Mac here: steps, sleep, food and habits."));
        }
        int waiting = engine.waiting();
        TextView w = ui.small(waiting == 0 ? "Nothing waiting to send" : waiting + (waiting == 1 ? " item" : " items") + " waiting · sent on the next sync");
        w.setGravity(Gravity.CENTER); col.addView(w);
        long at = prefs.getLong("todayAt", 0);
        if (at > 0) { TextView u = ui.small("From your Mac at " + clock(at)); u.setGravity(Gravity.CENTER); u.setTextSize(11); col.addView(u); }
        askNotificationsOnce();
        return holder[0];
    }
    View syncPill() {
        LinearLayout pill = ui.row(8);
        pill.setBackground(ui.round(Ui.PANEL, 18, Ui.LINE, 1)); ui.pad(pill, 14, 0, 14, 0);
        long last = prefs.getLong("lastSync", 0);
        boolean fresh = last > 0 && System.currentTimeMillis() - last < 3 * 3600 * 1000L;
        View dot = new View(this); dot.setBackground(ui.round(syncing ? Ui.ACCENT : fresh ? Ui.GREEN : Ui.FAINT, 4, 0, 0));
        pill.addView(dot, new LinearLayout.LayoutParams(ui.dp(8), ui.dp(8)));
        String label = syncing ? "Syncing with " + engine.macName() + "…"
            : !engine.paired() ? "Not paired · set up below"
            : last == 0 ? "Not synced yet · tap to sync"
            : "Synced " + ago(last) + " · " + engine.macName();
        pill.addView(ui.oneLine(ui.text(label, 12, Ui.SOFT, 500)));
        if (engine.paired() && !syncing) pill.addView(ui.iconView("ic_refresh", Ui.SOFT, 14));
        pill.setContentDescription(label);
        pill.setOnClickListener(Ui.tap(v -> sync(true, false)));
        return pill;
    }
    View setupCard() {
        LinearLayout card = ui.card(10);
        card.setBackground(ui.round(Ui.PANEL, 18, 0x59A18AFF, 1));
        card.addView(ui.text("Connect to your Mac", 17, Ui.TEXT, 600));
        card.addView(ui.body("1. On the Mac, open Ascend → Health → Pair phone.\n2. Tap Pair with Mac and check the 6-digit code matches.\n3. Choose which health data to share."));
        card.addView(ui.primary("Pair with Mac", v -> withNetwork(this::pair, null)), Ui.wide());
        card.addView(ui.secondary("Choose health data", v -> requestPermissions(SyncEngine.healthPermissions(), REQ_HEALTH)), Ui.wide());
        return card;
    }
    View actionTile(String icon, String label, View.OnClickListener l) {
        LinearLayout tile = ui.column(8); tile.setGravity(Gravity.CENTER);
        tile.setBackground(ui.round(Ui.PANEL, 16, Ui.LINE, 1));
        tile.addView(ui.badge(icon, Ui.ACCENT_SOFT, Ui.ACCENT, 40, 20));
        TextView text = ui.text(label, 13, Ui.TEXT, 500); text.setGravity(Gravity.CENTER);
        tile.addView(text);
        tile.setMinimumHeight(ui.dp(96)); tile.setContentDescription(label);
        tile.setOnClickListener(Ui.tap(l));
        return tile;
    }
    View lastNight(JSONObject t) {
        LinearLayout card = ui.card(12);
        card.addView(ui.text("Last night", 15, Ui.TEXT, 600));
        double sleep = t.optDouble("sleepHours", Double.NaN), hr = t.optDouble("restingHeartRate", Double.NaN), o2 = t.optDouble("oxygen", Double.NaN);
        double min = t.optDouble("sleepMin", Double.NaN), max = t.optDouble("sleepMax", Double.NaN);
        String goal = Double.isNaN(min) ? "From your watch" : "Goal " + fmt(min) + (Double.isNaN(max) ? "+" : "–" + fmt(max)) + " h";
        boolean short_ = !Double.isNaN(sleep) && !Double.isNaN(min) && sleep < min;
        card.addView(ui.grid(10,
            metric("Sleep", Double.isNaN(sleep) ? "—" : fmt(sleep), "h", Double.isNaN(sleep) || Double.isNaN(min) ? -1 : sleep / min, short_ ? Ui.ORANGE : Ui.ACCENT, short_ ? goal + " · short" : goal),
            metric("Resting HR", Double.isNaN(hr) ? "—" : fmt(Math.round(hr)), Double.isNaN(hr) ? "" : "bpm", -1, 0, Double.isNaN(hr) ? "No overnight samples" : "Lowest asleep"),
            metric("Oxygen", Double.isNaN(o2) ? "—" : fmt(o2), Double.isNaN(o2) ? "" : "%", -1, 0, Double.isNaN(o2) ? "No overnight samples" : "Average asleep")));
        return card;
    }
    View daySoFar(JSONObject t) {
        LinearLayout card = ui.card(16);
        LinearLayout head = ui.row(8);
        head.addView(ui.text("Your day so far", 15, Ui.TEXT, 600), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (t.optInt("mealsToReview") > 0) head.addView(ui.text(t.optInt("mealsToReview") + " meal" + (t.optInt("mealsToReview") == 1 ? "" : "s") + " to review", 12, Ui.ACCENT_TEXT, 500));
        card.addView(head);
        double steps = t.optDouble("steps", Double.NaN), stepGoal = t.optDouble("stepGoal", Double.NaN);
        double protein = t.optDouble("protein", 0), proteinGoal = t.optDouble("proteinGoal", Double.NaN);
        double kcal = t.optDouble("kcal", 0), limit = t.optDouble("kcalLimit", Double.NaN);
        // Habits have their own card above, so this row is the watch and food numbers.
        card.addView(ui.grid(14,
            metric("Steps", Double.isNaN(steps) ? "—" : fmt(steps), "", Double.isNaN(steps) || Double.isNaN(stepGoal) ? -1 : steps / stepGoal, Ui.ACCENT, Double.isNaN(stepGoal) ? "Today" : "of " + fmt(stepGoal)),
            metric("Protein", fmt(protein), "g", Double.isNaN(proteinGoal) ? -1 : protein / proteinGoal, Ui.ACCENT, Double.isNaN(proteinGoal) ? "Confirmed" : "of " + fmt(proteinGoal) + " g"),
            metric("Calories", fmt(kcal), "", Double.isNaN(limit) ? -1 : kcal / limit, kcal > (Double.isNaN(limit) ? Double.MAX_VALUE : limit) ? Ui.ORANGE : Ui.ACCENT,
                Double.isNaN(limit) ? "Confirmed" : kcal <= limit ? fmt(limit - kcal) + " left" : fmt(kcal - limit) + " over")));
        return card;
    }

    // MARK: Avatar and habits
    String habitFilter = "remaining";
    String goalFilter;
    /** The Mac's avatar card, compact: portrait, today's percentage against the target, and the three forms. */
    View avatarCard(JSONObject t) {
        LinearLayout card = ui.card(0);
        LinearLayout row = ui.row(16); row.setGravity(Gravity.CENTER_VERTICAL);
        String stage = t.optString("avatar", "Obsidian");
        int id = getResources().getIdentifier("portrait_" + stage.toLowerCase(Locale.ROOT), "drawable", getPackageName());
        ImageView portrait = new ImageView(this);
        if (id != 0) portrait.setImageDrawable(getDrawable(id));
        portrait.setScaleType(ImageView.ScaleType.CENTER_CROP);
        portrait.setBackground(ui.round(Ui.BG, 14, 0, 0)); portrait.setClipToOutline(true);
        portrait.setContentDescription("Your avatar, " + stage + " form");
        row.addView(portrait, new LinearLayout.LayoutParams(ui.dp(104), ui.dp(156)));
        LinearLayout info = ui.column(6);
        TextView k = ui.kicker("Your avatar · " + stage); k.setTextColor(Ui.ACCENT); info.addView(k);
        LinearLayout big = ui.row(6); big.setGravity(Gravity.BOTTOM);
        int due = t.optInt("habitsDue"), done = t.optInt("habitsDone");
        big.addView(ui.text(Math.round(t.optDouble("progress") * 100) + "%", 34, Ui.TEXT, 700));
        big.addView(ui.text(done + " of " + due, 13, Ui.MUTED, 500));
        info.addView(big);
        double target = t.optDouble("target", 0.75);
        FrameLayout bar = new FrameLayout(this);
        bar.addView(ui.bar(t.optDouble("progress"), Ui.ACCENT), new FrameLayout.LayoutParams(Ui.MATCH, ui.dp(4), Gravity.CENTER_VERTICAL));
        View marker = new View(this); marker.setBackgroundColor(Ui.SOFT);
        bar.addView(marker, new FrameLayout.LayoutParams(ui.dp(1), ui.dp(12)));
        bar.addOnLayoutChangeListener((v, l, top, r, b, ol, ot, or, ob) -> marker.setTranslationX((float) ((r - l) * target)));
        info.addView(bar, new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(12)));
        String line = t.optBoolean("rest") ? "Rest day. Recurring habits are paused."
            : due == 0 ? "Nothing scheduled today."
            : t.optInt("toTarget") > 0 ? t.optInt("toTarget") + " more to hit your " + Math.round(target * 100) + "% target."
            : "Target reached. Keep building.";
        info.addView(ui.small(line));
        String[] forms = {"Obsidian", "Titanium", "Ascendant"};
        LinearLayout steps = ui.row(10);
        for (int i = 0; i < forms.length; i++) {
            boolean on = forms[i].equals(stage);
            steps.addView(ui.text("0" + (i + 1) + " " + forms[i], 11, on ? Ui.ACCENT_TEXT : Ui.FAINT, on ? 600 : 500));
        }
        info.addView(steps);
        double evolution = t.optDouble("evolution");
        String nextForm = evolution >= 1 ? null : evolution >= 0.5 ? "Ascendant" : "Titanium";
        info.addView(ui.small(nextForm == null ? "Final form reached this cycle." : nextForm + " at " + (nextForm.equals("Titanium") ? 50 : 100) + "% · you’re at " + Math.round(evolution * 100) + "%"));
        row.addView(info, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        card.addView(row);
        return card;
    }
    /** Today's habits from the Mac, ticked here and sent like doses. */
    View habitsCard(JSONObject t) {
        LinearLayout card = ui.card(10);
        LinearLayout head = ui.row(8);
        head.addView(ui.text("Today’s habits", 15, Ui.TEXT, 600), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        for (String f : new String[]{"remaining", "all"}) {
            Button chip = ui.chip(f.equals("remaining") ? "Remaining" : "All", habitFilter.equals(f), v -> { habitFilter = f; render(); });
            head.addView(chip, new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(32)));
        }
        card.addView(head);
        if (t.optBoolean("rest")) { card.addView(ui.small("Rest day. Resume it on the Mac to log recurring habits.")); return card; }
        JSONArray goals = t.optJSONArray("goals");
        if (goals != null && goals.length() > 1) {
            HorizontalScrollView scroll = new HorizontalScrollView(this); scroll.setHorizontalScrollBarEnabled(false);
            LinearLayout strip = ui.row(8);
            for (int i = 0; i < goals.length(); i++) {
                JSONObject g = goals.optJSONObject(i);
                String title = g.optString("title");
                boolean on = title.equals(goalFilter);
                strip.addView(ui.chip(title + "  " + g.optInt("done") + "/" + g.optInt("due"), on, v -> { goalFilter = on ? null : title; render(); }), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(34)));
            }
            scroll.addView(strip);
            card.addView(scroll);
        }
        JSONArray habits = t.optJSONArray("habits");
        String period = null;
        int shown = 0;
        for (int i = 0; habits != null && i < habits.length(); i++) {
            JSONObject h = habits.optJSONObject(i);
            if (h == null || (habitFilter.equals("remaining") && h.optBoolean("done")) || (goalFilter != null && !goalFilter.equals(h.optString("goal")))) continue;
            if (!h.optString("period").equals(period)) {
                period = h.optString("period");
                TextView p = ui.kicker(period); p.setPadding(0, ui.dp(shown == 0 ? 2 : 10), 0, 0); card.addView(p);
            }
            card.addView(habitRow(h, t.optString("day")));
            shown++;
        }
        if (shown == 0) card.addView(ui.small(habitFilter.equals("remaining") ? "All done for now. Nice work." : "Nothing scheduled here today."));
        return card;
    }
    View habitRow(JSONObject h, String day) {
        boolean done = h.optBoolean("done"), metric = h.optString("kind").equals("metric");
        LinearLayout row = ui.row(12); ui.pad(row, 0, 8, 0, 8);
        View mark = done ? ui.badge("ic_check", Ui.ACCENT, Ui.ON_ACCENT, 28, 16) : new View(this);
        if (!done) mark.setBackground(ui.round(0, 14, Ui.MUTED, 1.5f));
        row.addView(mark, new LinearLayout.LayoutParams(ui.dp(28), ui.dp(28)));
        LinearLayout text = ui.column(2);
        TextView title = ui.oneLine(ui.text(h.optString("title"), 15, done ? Ui.MUTED : Ui.TEXT, 500));
        if (done) title.setPaintFlags(title.getPaintFlags() | android.graphics.Paint.STRIKE_THRU_TEXT_FLAG);
        text.addView(title);
        String sub = h.optString("goal") + (h.has("target") ? " · " + h.optString("target") : "") + (h.optBoolean("auto") ? " · auto" : "");
        text.addView(ui.oneLine(ui.small(sub)));
        row.addView(text, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (metric) {
            String unit = h.optString("unit", "");
            TextView value = ui.mono(h.has("value") ? fmt(h.optDouble("value")) + (unit.isEmpty() ? "" : " " + unit) : "Add", 13, h.has("value") ? Ui.TEXT : Ui.ACCENT_TEXT);
            value.setBackground(ui.round(Ui.PANEL2, 10, 0, 0)); ui.pad(value, 12, 8, 12, 8);
            row.addView(value);
        }
        row.setContentDescription(h.optString("title") + (done ? ", done" : ", not done"));
        row.setOnClickListener(Ui.tap(v -> { if (metric) numberDialog(h, day); else checkIn(h, day, !done, null, false); }));
        return row;
    }
    void checkIn(JSONObject h, String day, Boolean completed, Double value, boolean clear) {
        try { engine.recordCheckIn(h, day, completed, value, clear); }
        catch (Exception e) { toast("Couldn’t save that on this phone."); return; }
        render();
        sync(false, true);
    }
    void numberDialog(JSONObject h, String day) {
        EditText field = new EditText(this);
        field.setInputType(android.text.InputType.TYPE_CLASS_NUMBER | android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL);
        field.setTextColor(Ui.TEXT); field.setHintTextColor(Ui.FAINT); field.setHint(h.optString("target", h.optString("unit")));
        if (h.has("value")) { field.setText(fmt(h.optDouble("value")).replace(",", "")); field.setSelection(field.getText().length()); }
        FrameLayout wrap = new FrameLayout(this); ui.pad(wrap, 20, 8, 20, 0); wrap.addView(field);
        AlertDialog.Builder d = dialog().setTitle(h.optString("title"))
            .setMessage(h.optBoolean("auto") ? "Filled from your watch or meals. A number you enter here replaces it." : null)
            .setView(wrap)
            .setPositiveButton("Save", (x, w) -> {
                try { checkIn(h, day, null, Double.parseDouble(field.getText().toString().trim().replace(",", "")), false); }
                catch (NumberFormatException e) { toast("Enter a number."); }
            })
            .setNegativeButton("Cancel", null);
        if (h.has("value")) d.setNeutralButton("Clear", (x, w) -> checkIn(h, day, null, null, true));
        d.show();
    }

    // MARK: Doses
    List<JSONObject> dosesToday() {
        JSONArray all = ReminderReceiver.schedule(prefs);
        String today = LocalDate.now().toString();
        List<JSONObject> doses = new ArrayList<>();
        for (int i = 0; i < all.length(); i++) { JSONObject d = all.optJSONObject(i); if (d != null && today.equals(d.optString("day"))) doses.add(d); }
        doses.sort(Comparator.comparingInt(d -> d.optInt("minute")));
        return doses;
    }
    JSONObject nextDose() {
        for (JSONObject d : dosesToday()) if (!ReminderReceiver.taken(this, d)) return d;
        return null;
    }
    View nextDoseCard(JSONObject dose) {
        LinearLayout card = ui.card(0);
        card.setBackground(ui.round(Ui.PANEL, 18, 0x59A18AFF, 1));
        LinearLayout row = ui.row(14);
        LinearLayout text = ui.column(4);
        int minute = dose.optInt("minute");
        int now = LocalTime.now().getHour() * 60 + LocalTime.now().getMinute();
        String when = minute - now > 59 ? "in " + ((minute - now) / 60) + " h" + ((minute - now) % 60 == 0 ? "" : " " + ((minute - now) % 60) + " min")
            : minute - now > 0 ? "in " + (minute - now) + " min" : now - minute < 15 ? "due now" : "overdue " + ((now - minute) >= 60 ? (now - minute) / 60 + " h" : (now - minute) + " min");
        TextView k = ui.kicker("Next dose · " + hhmm(minute)); k.setTextColor(Ui.ACCENT); text.addView(k);
        text.addView(ui.oneLine(ui.text(dose.optString("name"), 17, Ui.TEXT, 600)));
        String detail = dose.optString("detail");
        text.addView(ui.small((detail.isEmpty() ? "" : detail + " · ") + when));
        row.addView(text, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        row.addView(ui.pill("Taken", v -> markDose(dose, true)), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(44)));
        card.addView(row);
        return card;
    }
    void markDose(JSONObject dose, boolean taken) {
        try { ReminderReceiver.record(this, dose, taken); } catch (Exception e) { toast("Couldn’t save that on this phone."); return; }
        getSystemService(NotificationManager.class).cancel(ReminderReceiver.code(ReminderReceiver.key(dose)));
        if (taken) toast(dose.optString("name") + " taken");
        render();
        sync(false, true);
    }
    void askNotificationsOnce() {
        if (ReminderReceiver.schedule(prefs).length() > 0 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            && !prefs.getBoolean("askedNotify", false)) {
            prefs.edit().putBoolean("askedNotify", true).apply();
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIFY);
        }
    }
    boolean remindersOn() { return checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED; }

    // MARK: Meals
    View meals() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(header("Photo → Claude estimate on your Mac", "Meals", null));
        View snap = ui.iconButton("Take meal photo", "ic_camera", ui.round(Ui.ACCENT, 16, 0, 0), Ui.ON_ACCENT, 56, v -> { photoMode = "meal"; takePhoto(); });
        View pick = ui.iconButton("Choose from gallery", "ic_gallery", ui.round(Ui.PANEL, 14, 0x1FFFFFFF, 1), Ui.TEXT, 48, v -> { photoMode = "meal"; choosePhotos(4); });
        LinearLayout buttons = ui.column(10); buttons.addView(snap, Ui.wide()); buttons.addView(pick, Ui.wide());
        col.addView(buttons);
        File[] waiting = engine.queuedMeals();
        LinearLayout section = ui.column(10);
        LinearLayout head = ui.row(8);
        head.addView(ui.text("Waiting to send · " + waiting.length, 15, Ui.TEXT, 600), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (waiting.length > 0) head.addView(ui.small("Sends on next sync"));
        section.addView(head);
        if (waiting.length == 0) section.addView(ui.small("No photos waiting. New photos go to your Mac on the next sync, and Claude estimates them there."));
        for (int i = 0; i < waiting.length; i += 2) {
            View a = mealCard(waiting[i]);
            View b = i + 1 < waiting.length ? mealCard(waiting[i + 1]) : new View(this);
            section.addView(ui.grid(10, a, b));
        }
        col.addView(section);
        JSONObject t = engine.today();
        if (t.length() > 0) {
            LinearLayout card = ui.card(12);
            LinearLayout h = ui.row(8);
            h.addView(ui.text("Confirmed today", 15, Ui.TEXT, 600), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            if (t.optInt("mealsToReview") > 0) h.addView(ui.small(t.optInt("mealsToReview") + " to review on Mac"));
            card.addView(h);
            double limit = t.optDouble("kcalLimit", Double.NaN), goal = t.optDouble("proteinGoal", Double.NaN);
            card.addView(ui.grid(24,
                metric("Calories", fmt(t.optDouble("kcal", 0)), "kcal", -1, 0, Double.isNaN(limit) ? "Today" : "of ≤ " + fmt(limit)),
                metric("Protein", fmt(t.optDouble("protein", 0)), "g", -1, 0, Double.isNaN(goal) ? "Today" : "of " + fmt(goal) + " g")));
            card.addView(ui.small("Confirm or adjust each estimate on your Mac; confirmed meals fill your calorie and protein check-ins."));
            col.addView(card);
        }
        return holder[0];
    }
    View mealCard(File meta) {
        LinearLayout card = ui.column(0);
        card.setBackground(ui.round(Ui.PANEL, 16, Ui.LINE, 1)); card.setClipToOutline(true);
        String note = "", time = "";
        File photo = null;
        try {
            JSONObject m = SyncEngine.readJSON(meta);
            note = m.optString("note"); time = clock(m.optLong("takenAt") * 1000);
            photo = new File(engine.mealsDir(), m.getString("id") + ".jpg");
        } catch (Exception ignored) {}
        card.addView(thumb(photo), new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(104)));
        LinearLayout text = ui.column(2); ui.pad(text, 12, 10, 12, 10);
        text.addView(ui.oneLine(ui.text(note.isEmpty() ? "No note" : note, 13, note.isEmpty() ? Ui.MUTED : Ui.TEXT, 500)));
        text.addView(ui.mono(time, 11, Ui.MUTED));
        card.addView(text);
        File photoFile = photo;
        card.setOnLongClickListener(v -> {
            dialog().setTitle("Remove this meal photo?").setMessage("It hasn’t been sent yet.")
                .setPositiveButton("Remove", (d, w) -> { if (photoFile != null) photoFile.delete(); meta.delete(); render(); })
                .setNegativeButton("Keep", null).show();
            return true;
        });
        return card;
    }
    View thumb(File photo) {
        ImageView image = new ImageView(this);
        image.setScaleType(ImageView.ScaleType.CENTER_CROP); image.setBackgroundColor(Ui.PANEL2);
        if (photo != null && photo.exists()) {
            Bitmap b = thumbs.get(photo.getPath());
            if (b == null) {
                BitmapFactory.Options o = new BitmapFactory.Options(); o.inSampleSize = 4;
                b = BitmapFactory.decodeFile(photo.getPath(), o);
                if (b != null) thumbs.put(photo.getPath(), b);
            }
            if (b != null) image.setImageBitmap(b);
        }
        return image;
    }

    // MARK: Medicines
    View meds() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        LinearLayout pill = ui.row(6);
        pill.setBackground(ui.round(Ui.PANEL, 15, Ui.LINE, 1)); ui.pad(pill, 12, 0, 12, 0);
        pill.addView(ui.iconView("ic_bell", remindersOn() ? Ui.SOFT : Ui.ORANGE, 14));
        pill.addView(ui.text(remindersOn() ? "Reminders on" : "Turn on reminders", 12, remindersOn() ? Ui.SOFT : Ui.ORANGE, 500));
        pill.setOnClickListener(Ui.tap(v -> enableReminders()));
        pill.setLayoutParams(new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(30)));
        col.addView(header("As your doctor prescribed", "Medicines", pill));
        List<JSONObject> doses = dosesToday();
        int takenCount = 0;
        for (JSONObject d : doses) if (ReminderReceiver.taken(this, d)) takenCount++;
        LinearLayout card = ui.card(4);
        LinearLayout head = ui.row(8);
        head.addView(ui.text("Today", 15, Ui.TEXT, 600), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (!doses.isEmpty()) head.addView(ui.small(takenCount + " of " + doses.size() + " taken"));
        card.addView(head);
        if (doses.isEmpty()) {
            TextView empty = ui.small(ReminderReceiver.schedule(prefs).length() == 0
                ? "Your medicines appear here once you confirm them on your Mac and sync."
                : "Nothing scheduled today.");
            empty.setPadding(0, ui.dp(8), 0, 0); card.addView(empty);
        } else {
            View bar = ui.bar((double) takenCount / doses.size(), Ui.ACCENT);
            LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(4)); bp.setMargins(0, ui.dp(8), 0, ui.dp(6));
            card.addView(bar, bp);
            for (int i = 0; i < doses.size(); i++) { if (i > 0) card.addView(ui.divider()); card.addView(doseRow(doses.get(i))); }
        }
        col.addView(card);
        JSONObject t = engine.today();
        if (t.has("medsWeekTaken") && (t.optInt("medsWeekTaken") + t.optInt("medsWeekMissed")) > 0) {
            col.addView(ui.grid(10,
                stat("Last 7 days", t.optInt("medsWeekTaken") + " taken", t.optInt("medsWeekMissed") + " missed", t.optInt("medsWeekMissed") > 0 ? Ui.ORANGE : Ui.MUTED),
                stat("Today", takenCount + " of " + doses.size(), "Habit ticks when all taken", Ui.MUTED)));
        }
        col.addView(ui.iconButton("Add medicines with photos", "ic_plus", ui.dashed(Ui.PANEL, 16, 0x8CA18AFF), Ui.ACCENT_TEXT, 52, v -> show(Screen.ADD_MEDS)), Ui.wide());
        int open = SyncEngine.json(engine.openMedBatch()).length, ready = engine.readyMedPhotos();
        TextView note = ui.small(ready > 0 ? ready + " medicine photo" + (ready == 1 ? "" : "s") + " waiting to send"
            : open > 0 ? open + " photo" + (open == 1 ? "" : "s") + " in an unfinished batch · tap Add medicines to finish"
            : "New medicines show here after you confirm them on your Mac.");
        note.setGravity(Gravity.CENTER); col.addView(note);
        return holder[0];
    }
    View doseRow(JSONObject dose) {
        boolean taken = ReminderReceiver.taken(this, dose);
        LinearLayout row = ui.row(12); ui.pad(row, 0, 10, 0, 10);
        row.addView(ui.mono(hhmm(dose.optInt("minute")), 14, taken ? Ui.MUTED : Ui.TEXT), new LinearLayout.LayoutParams(ui.dp(52), Ui.WRAP));
        LinearLayout text = ui.column(3);
        TextView name = ui.oneLine(ui.text(dose.optString("name"), 15, taken ? Ui.MUTED : Ui.TEXT, 500));
        if (taken) name.setPaintFlags(name.getPaintFlags() | android.graphics.Paint.STRIKE_THRU_TEXT_FLAG);
        text.addView(name);
        String detail = dose.optString("detail");
        if (!detail.isEmpty()) text.addView(ui.oneLine(ui.small(detail)));
        row.addView(text, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (taken) {
            FrameLayout done = ui.badge("ic_check", Ui.ACCENT, Ui.ON_ACCENT, 44, 20);
            done.setContentDescription("Taken. Tap to undo.");
            done.setOnClickListener(Ui.tap(v -> markDose(dose, false)));
            row.addView(done);
        } else {
            Button b = ui.outline("Taken", v -> markDose(dose, true));
            row.addView(b, new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(44)));
        }
        return row;
    }
    void enableReminders() {
        if (remindersOn()) { toast("Reminders are on. Manage them in Android Settings → Notifications."); return; }
        if (!prefs.getBoolean("askedNotify", false)) { prefs.edit().putBoolean("askedNotify", true).apply(); requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIFY); return; }
        startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()));
    }

    // MARK: Add medicines (one batch, any order)
    View addMeds() {
        FrameLayout frame = new FrameLayout(this);
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, false);
        File batch = engine.openMedBatch();
        File[] photos = SyncEngine.json(batch);
        col.addView(topBar("Add medicines", Screen.MEDS, ui.mono(photos.length + " / " + SyncEngine.MAX_MED_PHOTOS, 13, Ui.MUTED)));
        TextView intro = ui.body("Photograph every side of each medicine (front, back, strip) in any order. Claude sorts them into medicines on your Mac.");
        col.addView(intro);
        List<View> tiles = new ArrayList<>();
        tiles.add(squareTile("ic_camera", "Camera", true, v -> { if (full(photos)) return; photoMode = "med"; takePhoto(); }));
        tiles.add(squareTile("ic_gallery", "Gallery", false, v -> { if (full(photos)) return; photoMode = "med"; choosePhotos(SyncEngine.MAX_MED_PHOTOS - photos.length); }));
        for (File meta : photos) tiles.add(batchPhoto(batch, meta));
        for (int i = 0; i < tiles.size(); i += 3) {
            View a = tiles.get(i), b = i + 1 < tiles.size() ? tiles.get(i + 1) : new View(this), c = i + 2 < tiles.size() ? tiles.get(i + 2) : new View(this);
            LinearLayout row = ui.grid(10, a, b, c);
            for (int k = 0; k < row.getChildCount(); k++) row.getChildAt(k).getLayoutParams().height = ui.dp(104);
            col.addView(row);
        }
        TextView tip = ui.small("Tip: include at least one photo that shows each medicine’s name. Photos Claude can’t place wait in “Not sure” on your Mac.");
        tip.setBackground(ui.round(Ui.PANEL, 14, Ui.LINE, 1)); ui.pad(tip, 14, 12, 14, 12);
        col.addView(tip);
        frame.addView(holder[0], new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        LinearLayout bottom = ui.row(10);
        bottom.setBackgroundColor(Ui.BG); bottom.setPadding(ui.dp(20), ui.dp(16), ui.dp(20), insetBottom + ui.dp(16));
        bottom.addView(ui.secondary("Later", v -> show(Screen.MEDS)), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(52)));
        Button done = ui.primary(photos.length == 0 ? "Add photos to send" : "Done · send " + photos.length + (photos.length == 1 ? " photo" : " photos"), v -> finishMedBatch(batch, photos.length));
        done.setEnabled(photos.length > 0); done.setAlpha(photos.length > 0 ? 1f : 0.4f);
        bottom.addView(done, new LinearLayout.LayoutParams(0, ui.dp(52), 1));
        frame.addView(bottom, new FrameLayout.LayoutParams(Ui.MATCH, Ui.WRAP, Gravity.BOTTOM));
        return frame;
    }
    boolean full(File[] photos) {
        if (photos.length < SyncEngine.MAX_MED_PHOTOS) return false;
        toast("That’s 20 photos, the most per batch. Tap Done, then start another.");
        return true;
    }
    View squareTile(String icon, String label, boolean accent, View.OnClickListener l) {
        LinearLayout tile = ui.column(6); tile.setGravity(Gravity.CENTER);
        tile.setBackground(accent ? ui.round(Ui.ACCENT_SOFT, 16, 0x99A18AFF, 1.5f) : ui.round(Ui.PANEL, 16, 0x1FFFFFFF, 1));
        tile.addView(ui.iconView(icon, accent ? Ui.ACCENT_TEXT : Ui.TEXT, 26));
        TextView text = ui.text(label, 13, accent ? Ui.ACCENT_TEXT : Ui.TEXT, accent ? 600 : 500); text.setGravity(Gravity.CENTER);
        tile.addView(text);
        tile.setContentDescription(label); tile.setOnClickListener(Ui.tap(l));
        return tile;
    }
    View batchPhoto(File batch, File meta) {
        FrameLayout f = new FrameLayout(this);
        f.setBackground(ui.round(Ui.PANEL2, 16, 0, 0)); f.setClipToOutline(true);
        File photo = new File(batch, meta.getName().replace(".json", ".jpg"));
        f.addView(thumb(photo), new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        FrameLayout remove = ui.badge("ic_close", 0x99000000, Ui.TEXT, 28, 14);
        remove.setContentDescription("Remove photo");
        remove.setOnClickListener(Ui.tap(v -> { photo.delete(); meta.delete(); thumbs.remove(photo.getPath()); render(); }));
        FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(ui.dp(28), ui.dp(28), Gravity.TOP | Gravity.END); rp.setMargins(0, ui.dp(4), ui.dp(4), 0);
        f.addView(remove, rp);
        return f;
    }
    void finishMedBatch(File batch, int n) {
        try (OutputStream out = new FileOutputStream(new File(batch, "ready.json"))) { out.write(SyncEngine.bytes(new JSONObject().put("size", n))); }
        catch (Exception e) { toast("Couldn’t save the batch on this phone."); return; }
        prefs.edit().remove("medBatch").apply();
        show(Screen.MEDS);
        if (engine.paired()) sync(false, false); else toast("Saved. Pair with your Mac to send these photos.");
    }

    // MARK: Urges
    View urges() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(header("A moment, not a verdict", "Urges", null));
        LinearLayout choices = ui.row(10);
        choices.addView(urgeTile("Let it pass", true)); choices.addView(urgeTile("Acted on it", false));
        col.addView(choices);
        JSONObject c = engine.urgeCounts();
        if (c.length() > 0) {
            col.addView(ui.grid(10,
                urgeStat("Today", c.optInt("todayPassed"), c.optInt("todayActed")),
                urgeStat("7 days", c.optInt("weekPassed"), c.optInt("weekActed")),
                urgeStat("Cycle", c.optInt("cyclePassed"), c.optInt("cycleActed"))));
            LinearLayout streak = ui.card(4);
            int days = c.optInt("cleanDays");
            streak.addView(ui.text(days + (days == 1 ? " day" : " days") + " since last acted on", 15, Ui.TEXT, 600));
            streak.addView(ui.small(days == 0 ? "A fresh start from here." : "Keep noticing; every pass counts."));
            col.addView(streak);
        } else col.addView(ui.small("Your counts appear after the first sync."));
        JSONArray history = urgeHistory();
        if (history.length() > 0) {
            LinearLayout recent = ui.column(0);
            recent.addView(ui.text("Recent on this phone", 15, Ui.TEXT, 600));
            for (int i = 0; i < Math.min(history.length(), 6); i++) {
                JSONObject h = history.optJSONObject(i);
                LinearLayout row = ui.row(12); ui.pad(row, 0, 10, 0, 10);
                row.addView(ui.mono(clock(h.optLong("at")), 14, Ui.MUTED), new LinearLayout.LayoutParams(ui.dp(52), Ui.WRAP));
                boolean acted = h.optString("outcome").equals("Acted on it");
                row.addView(ui.text(h.optString("outcome"), 14, acted ? Ui.ORANGE : Ui.TEXT, 400), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                LocalDate day = Instant.ofEpochMilli(h.optLong("at")).atZone(ZoneId.systemDefault()).toLocalDate();
                row.addView(ui.small(day.equals(LocalDate.now()) ? "Today" : day.equals(LocalDate.now().minusDays(1)) ? "Yesterday" : day.toString()));
                recent.addView(row);
            }
            col.addView(recent);
        }
        int waiting = engine.queuedUrges().length;
        if (waiting > 0) { TextView w = ui.small(waiting + (waiting == 1 ? " urge" : " urges") + " waiting to send"); w.setGravity(Gravity.CENTER); col.addView(w); }
        return holder[0];
    }
    View urgeTile(String outcome, boolean pass) {
        LinearLayout tile = ui.column(0);
        tile.setBackground(pass ? ui.round(Ui.ACCENT_SOFT, 20, 0x99A18AFF, 1.5f) : ui.round(Ui.PANEL, 20, 0x1FFFFFFF, 1));
        ui.pad(tile, 16, 16, 16, 16);
        tile.addView(pass ? ui.badge("ic_check", Ui.ACCENT, Ui.ON_ACCENT, 36, 20) : ui.badge("ic_urge", Ui.PANEL2, Ui.ORANGE, 36, 20));
        View gap = new View(this); tile.addView(gap, new LinearLayout.LayoutParams(1, 0, 1));
        tile.addView(ui.text(outcome, 17, Ui.TEXT, 600));
        // A fixed height: with a flexible one, the spacer above stretched the tile to the whole page.
        tile.setLayoutParams(new LinearLayout.LayoutParams(0, ui.dp(120), 1)); tile.setContentDescription(outcome);
        tile.setOnClickListener(Ui.tap(v -> logUrge(outcome)));
        return tile;
    }
    JSONArray urgeHistory() { try { return new JSONArray(prefs.getString("urgeHistory", "[]")); } catch (JSONException e) { return new JSONArray(); } }
    /** Saves the urge at once, then offers optional details; it's sent when the sheet closes. */
    void logUrge(String outcome) {
        long now = System.currentTimeMillis();
        File file;
        try {
            JSONObject urge = new JSONObject().put("id", UUID.randomUUID().toString()).put("takenAt", now / 1000).put("outcome", outcome).put("note", "");
            file = new File(engine.urgesDir(), urge.getString("id") + ".json");
            try (OutputStream out = new FileOutputStream(file)) { out.write(SyncEngine.bytes(urge)); }
            JSONArray history = urgeHistory(), next = new JSONArray().put(new JSONObject().put("at", now).put("outcome", outcome));
            for (int i = 0; i < Math.min(history.length(), 19); i++) next.put(history.get(i));
            prefs.edit().putString("urgeHistory", next.toString()).apply();
        } catch (Exception e) { toast("Couldn’t save the urge on this phone."); return; }
        render();
        urgeSheet(file, outcome, now);
    }
    void urgeSheet(File file, String outcome, long at) {
        Dialog sheet = new Dialog(this);
        sheet.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout box = ui.column(18);
        GradientDrawable bg = new GradientDrawable(); bg.setColor(Ui.PANEL);
        float r = ui.dp(24); bg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        box.setBackground(bg); box.setPadding(ui.dp(20), ui.dp(12), ui.dp(20), insetBottom + ui.dp(24));
        View handle = new View(this); handle.setBackground(ui.round(0x33FFFFFF, 2, 0, 0));
        LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(ui.dp(40), ui.dp(4)); hp.gravity = Gravity.CENTER_HORIZONTAL;
        box.addView(handle, hp);
        LinearLayout head = ui.row(12);
        boolean pass = outcome.equals("Let it pass");
        head.addView(pass ? ui.badge("ic_check", Ui.ACCENT, Ui.ON_ACCENT, 40, 20) : ui.badge("ic_urge", Ui.PANEL2, Ui.ORANGE, 40, 20));
        LinearLayout titles = ui.column(2);
        titles.addView(ui.text(outcome, 20, Ui.TEXT, 700));
        titles.addView(ui.small("Saved at " + clock(at) + " · details are optional"));
        head.addView(titles);
        box.addView(head);
        int[] intensity = {0};
        String[] trigger = {null};
        box.addView(ui.text("How strong?", 12, Ui.MUTED, 600));
        LinearLayout levels = ui.row(8);
        Button[] levelButtons = new Button[5];
        for (int i = 1; i <= 5; i++) {
            int level = i;
            Button b = ui.chip(String.valueOf(i), false, v -> {});
            b.setOnClickListener(Ui.tap(v -> {
                intensity[0] = intensity[0] == level ? 0 : level;
                for (int k = 0; k < 5; k++) styleChip(levelButtons[k], intensity[0] == k + 1);
            }));
            levelButtons[i - 1] = b;
            levels.addView(b, new LinearLayout.LayoutParams(0, ui.dp(44), 1));
        }
        box.addView(levels);
        box.addView(ui.text("What was happening?", 12, Ui.MUTED, 600));
        Button[] triggerButtons = new Button[TRIGGERS.length];
        LinearLayout chips = ui.column(8), line = null;
        for (int i = 0; i < TRIGGERS.length; i++) {
            if (i % 3 == 0) { line = ui.row(8); chips.addView(line); }
            String name = TRIGGERS[i];
            Button b = ui.chip(name, false, v -> {});
            b.setOnClickListener(Ui.tap(v -> {
                trigger[0] = name.equals(trigger[0]) ? null : name;
                for (int k = 0; k < TRIGGERS.length; k++) styleChip(triggerButtons[k], TRIGGERS[k].equals(trigger[0]));
            }));
            triggerButtons[i] = b;
            line.addView(b, new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
        }
        box.addView(chips);
        EditText note = new EditText(this);
        note.setHint("Note (optional)"); note.setHintTextColor(Ui.FAINT); note.setTextColor(Ui.TEXT); note.setTextSize(14);
        note.setBackground(ui.round(Ui.BG, 12, 0x1FFFFFFF, 1)); ui.pad(note, 14, 0, 14, 0); note.setSingleLine(true);
        box.addView(note, new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(48)));
        LinearLayout buttons = ui.row(10);
        boolean[] saved = {false};
        buttons.addView(ui.secondary("Skip", v -> sheet.dismiss()), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(52)));
        buttons.addView(ui.primary("Save details", v -> {
            try {
                JSONObject urge = SyncEngine.readJSON(file);
                if (intensity[0] > 0) urge.put("intensity", intensity[0]);
                if (trigger[0] != null) urge.put("trigger", trigger[0]);
                String text = note.getText().toString().trim();
                urge.put("note", text.length() > 500 ? text.substring(0, 500) : text);
                try (OutputStream out = new FileOutputStream(file)) { out.write(SyncEngine.bytes(urge)); }
                saved[0] = true;
            } catch (Exception ignored) {}
            sheet.dismiss();
        }), new LinearLayout.LayoutParams(0, ui.dp(52), 1));
        box.addView(buttons);
        sheet.setContentView(box);
        sheet.setOnDismissListener(d -> { toast(saved[0] ? "Urge saved with details" : "Urge saved"); render(); sync(false, true); });
        Window w = sheet.getWindow();
        w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        w.setLayout(Ui.MATCH, Ui.WRAP); w.setGravity(Gravity.BOTTOM);
        w.setDimAmount(0.55f);
        sheet.show();
    }
    void styleChip(Button b, boolean on) {
        b.setBackground(on ? ui.round(Ui.ACCENT_SOFT, 18, Ui.ACCENT, 1) : ui.round(Ui.PANEL2, 18, 0, 0));
        b.setTextColor(on ? 0xFFE0D8FF : Ui.TEXT);
    }

    // MARK: Settings
    View settings() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, false);
        col.addView(topBar("Settings", Screen.TODAY, null));
        LinearLayout mac = ui.card(12);
        mac.addView(ui.kicker("Your Mac"));
        if (engine.paired()) {
            LinearLayout row = ui.row(10);
            long last = prefs.getLong("lastSync", 0);
            View dot = new View(this); dot.setBackground(ui.round(last > 0 ? Ui.GREEN : Ui.FAINT, 5, 0, 0));
            row.addView(dot, new LinearLayout.LayoutParams(ui.dp(10), ui.dp(10)));
            LinearLayout t = ui.column(2);
            t.addView(ui.text(engine.macName(), 15, Ui.TEXT, 600));
            t.addView(ui.small("Paired · same Wi-Fi · " + (last > 0 ? "last sync " + clock(last) : "not synced yet")));
            row.addView(t);
            mac.addView(row);
            String message = prefs.getString("lastSyncMessage", "");
            if (!message.isEmpty()) mac.addView(ui.small(String.join(" · ", message.split("\n"))));
            mac.addView(ui.grid(10, ui.primary(syncing ? "Syncing…" : "Sync now", v -> sync(true, false)), ui.danger("Forget Mac", v -> forget())));
        } else {
            mac.addView(ui.body("Not paired. On the Mac, open Ascend → Health → Pair phone, then tap Pair with Mac."));
            mac.addView(ui.primary("Pair with Mac", v -> withNetwork(this::pair, null)), Ui.wide());
        }
        col.addView(mac);
        LinearLayout health = ui.card(10);
        health.addView(ui.kicker("Health data"));
        LinearLayout hr = ui.row(10);
        LinearLayout ht = ui.column(2);
        ht.addView(ui.text("Mi Fitness via Health Connect", 15, Ui.TEXT, 500));
        ht.addView(ui.small(engine.allowedCount() + " of " + SyncEngine.KEYS.length + " types allowed · last 14 days"));
        hr.addView(ht, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        Button manage = ui.chip("Manage", false, v -> requestPermissions(SyncEngine.healthPermissions(), REQ_HEALTH));
        hr.addView(manage, new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
        health.addView(hr);
        col.addView(health);
        LinearLayout sync = ui.card(14);
        sync.addView(ui.kicker("Syncing"));
        sync.addView(toggle("Sync in the background", engine.backgroundAllowed() ? "Every hour on Wi-Fi when your Mac is reachable" : "Needs “Access data in the background” in Health Connect",
            prefs.getBoolean("backgroundSync", false) && engine.backgroundAllowed(), on -> {
                if (on && !engine.backgroundAllowed()) { requestPermissions(new String[]{SyncEngine.BACKGROUND}, REQ_BACKGROUND); return; }
                prefs.edit().putBoolean("backgroundSync", on).apply();
                boolean scheduled = SyncJob.schedule(this, on);
                toast(!on ? "Background sync off" : scheduled ? "Background sync on" : "Android didn’t allow the background job. Try again later."); render();
            }));
        sync.addView(toggle("Sync when I open the app", "Quietly sends anything waiting", prefs.getBoolean("autoSync", true), on -> prefs.edit().putBoolean("autoSync", on).apply()));
        sync.addView(toggle("Medicine reminders", remindersOn() ? "At each prescribed time, with a Taken button" : "Notifications are off for Ascend Bridge", remindersOn(), on -> enableReminders()));
        col.addView(sync);
        LinearLayout privacy = ui.column(8); ui.pad(privacy, 4, 4, 4, 0);
        privacy.addView(ui.kicker("Privacy"));
        privacy.addView(ui.small("Reads only the Mi Fitness records you allow and never writes health data. Photos are resized and stripped of location. Everything goes straight to your Mac over Wi-Fi, encrypted with the key from pairing. No account, cloud or developer options."));
        col.addView(privacy);
        TextView version = ui.small("Ascend Bridge " + VERSION); version.setGravity(Gravity.CENTER); version.setTextSize(11);
        col.addView(version);
        return holder[0];
    }
    View toggle(String title, String subtitle, boolean on, Consumer<Boolean> changed) {
        LinearLayout row = ui.row(12);
        LinearLayout t = ui.column(2);
        t.addView(ui.text(title, 15, Ui.TEXT, 500));
        t.addView(ui.small(subtitle));
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        Switch s = new Switch(this);
        s.setChecked(on);
        s.setThumbTintList(Ui.tint(Ui.TEXT, Ui.MUTED)); s.setTrackTintList(Ui.tint(Ui.ACCENT, 0xFF3A3642));
        s.setOnCheckedChangeListener((b, value) -> changed.accept(value));
        s.setContentDescription(title);
        row.addView(s);
        return row;
    }

    // MARK: Syncing
    /** Sends queued items, and health data when `health` is set and the screen is open. `quiet` hides routine messages. */
    void sync(boolean health, boolean quiet) {
        if (!engine.paired()) { if (!quiet) toast("Pair with your Mac first, in Settings."); return; }
        if (!SyncEngine.RUNNING.compareAndSet(false, true)) { if (!quiet) toast("Already syncing…"); return; }
        syncing = true; render();
        withNetwork(() -> engine.discover(list -> chooseTarget(list, quiet, target -> {
            if (target == null) { finishSync(quiet ? null : "Couldn’t find " + engine.macName() + " on this Wi-Fi. Open Ascend on the Mac and try again."); return; }
            if (health && engine.allowedCount() > 0 && readableForeground()) {
                getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                engine.readHealth(this::readableForeground, (snapshot, problem) ->
                    network.execute(() -> finishSync(engine.sendAll(target, snapshot, problem == null ? "" : problem + "\n"))));
            } else network.execute(() -> finishSync(engine.sendAll(target, null, "")));
        })), () -> finishSync("Ascend Bridge needs local network access to reach your Mac. Allow it in Settings → Apps → Ascend Bridge."));
    }
    void chooseTarget(List<SyncEngine.Target> list, boolean quiet, Consumer<SyncEngine.Target> chosen) {
        SyncEngine.Target preferred = engine.preferred(list);
        if (preferred != null || list.isEmpty() || quiet) { chosen.accept(preferred); return; }
        String[] names = list.stream().map(t -> t.name).toArray(String[]::new);
        dialog().setTitle("Choose your Mac").setItems(names, (d, i) -> chosen.accept(list.get(i)))
            .setOnCancelListener(d -> chosen.accept(null)).show();
    }
    void finishSync(String message) {
        runUi(() -> {
            SyncEngine.RUNNING.set(false); syncing = false;
            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            toast(message); render();
        });
    }
    boolean readableForeground() {
        android.os.PowerManager power = getSystemService(android.os.PowerManager.class);
        android.app.KeyguardManager lock = getSystemService(android.app.KeyguardManager.class);
        return hasWindowFocus() && power.isInteractive() && !lock.isKeyguardLocked();
    }
    /** Newer Android versions may ask before an app can reach devices on the local network. */
    void withNetwork(Runnable action, Runnable denied) {
        boolean needed;
        try {
            PermissionInfo info = getPackageManager().getPermissionInfo(LOCAL_NETWORK, 0);
            needed = info.getProtection() == PermissionInfo.PROTECTION_DANGEROUS && checkSelfPermission(LOCAL_NETWORK) != PackageManager.PERMISSION_GRANTED;
        } catch (PackageManager.NameNotFoundException e) { needed = false; }
        if (!needed) { action.run(); return; }
        afterNetwork = action; networkDenied = denied;
        requestPermissions(new String[]{LOCAL_NETWORK}, REQ_NETWORK);
    }
    @Override public void onRequestPermissionsResult(int code, String[] p, int[] granted) {
        super.onRequestPermissionsResult(code, p, granted);
        boolean ok = granted.length > 0 && granted[0] == PackageManager.PERMISSION_GRANTED;
        if (code == REQ_NETWORK) {
            Runnable action = afterNetwork, denied = networkDenied; afterNetwork = null; networkDenied = null;
            if (ok && action != null) action.run();
            else if (denied != null) denied.run();
            else toast("Ascend Bridge needs local network access to reach your Mac. Allow it in Settings → Apps → Ascend Bridge.");
        } else if (code == REQ_BACKGROUND) {
            prefs.edit().putBoolean("backgroundSync", ok).apply();
            boolean scheduled = SyncJob.schedule(this, ok);
            toast(!ok ? "Background sync needs “Access data in the background” for Ascend Bridge in Health Connect."
                : scheduled ? "Background sync on: every hour on Wi-Fi when your Mac is reachable." : "Android didn’t allow the background job. Try again later.");
        } else if (code == REQ_HEALTH) {
            if (prefs.getBoolean("backgroundSync", false) || engine.backgroundAllowed()) { prefs.edit().putBoolean("backgroundSync", engine.backgroundAllowed()).apply(); SyncJob.schedule(this, engine.backgroundAllowed()); }
            toast(engine.allowedCount() + " of " + SyncEngine.KEYS.length + " health types allowed");
        }
        render();
    }
    AlertDialog.Builder dialog() { return new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert); }

    // MARK: Pairing
    void pair() {
        if (!SyncEngine.RUNNING.compareAndSet(false, true)) { toast("Busy syncing. Try again in a moment."); return; }
        toast("Looking for Ascend on your Wi-Fi…");
        engine.discover(list -> {
            if (list.isEmpty()) { SyncEngine.RUNNING.set(false); toast("No Mac found. Open Ascend on your Mac and keep both devices on the same Wi-Fi."); return; }
            if (list.size() == 1) { network.execute(() -> pairWith(list.get(0))); return; }
            String[] names = list.stream().map(t -> t.name).toArray(String[]::new);
            dialog().setTitle("Choose your Mac").setItems(names, (d, i) -> network.execute(() -> pairWith(list.get(i))))
                .setOnCancelListener(d -> SyncEngine.RUNNING.set(false)).show();
        });
    }
    void pairWith(SyncEngine.Target t) {
        AlertDialog[] shown = new AlertDialog[1];
        try {
            KeyPair pair = LinkCrypto.newKeyPair();
            JSONObject start = new JSONObject().put("phoneID", engine.phoneID()).put("phoneName", Build.MODEL).put("phoneKey", LinkCrypto.encode(pair.getPublic()));
            LinkClient.Response r = LinkClient.post(t.host, t.port, "/pair/start", Collections.emptyMap(), SyncEngine.bytes(start), 8000);
            if (r.status != 200) { finishPairing(SyncEngine.error(r)); return; }
            JSONObject reply = new JSONObject(r.text());
            PublicKey mac = LinkCrypto.decode(reply.getString("macKey"));
            byte[] key = LinkCrypto.sessionKey(pair.getPrivate(), pair.getPublic(), mac);
            String code = LinkCrypto.pairingCode(mac, pair.getPublic());
            String macName = reply.optString("macName", t.name);
            pairingCancelled = false;
            runUi(() -> shown[0] = dialog().setTitle("Pair with " + macName)
                .setMessage("Check that your Mac shows\n\n" + code.substring(0, 3) + " " + code.substring(3) + "\n\nthen click “Codes match · Pair” on the Mac.")
                .setNegativeButton("Cancel", (d, w) -> pairingCancelled = true).setCancelable(false).show());
            long deadline = System.currentTimeMillis() + 180_000;
            while (!pairingCancelled && System.currentTimeMillis() < deadline) {
                LinkClient.Response c = LinkClient.post(t.host, t.port, "/pair/confirm", Collections.singletonMap("X-Ascend-Phone", engine.phoneID()), LinkCrypto.seal(SyncEngine.bytes(SyncEngine.envelope("pair")), key), 8000);
                if (c.status == 202) { Thread.sleep(1500); continue; }
                runUi(() -> { if (shown[0] != null) shown[0].dismiss(); });
                if (c.status != 200) { finishPairing(SyncEngine.error(c)); return; }
                JSONObject ok = new JSONObject(new String(LinkCrypto.open(c.body, key), StandardCharsets.UTF_8));
                prefs.edit().putString("key", Base64.getEncoder().encodeToString(key)).putString("macName", macName).putString("service", t.name).apply();
                finishPairing(ok.optString("message", "Paired") + ". Choose your health data next, then sync.");
                return;
            }
            runUi(() -> { if (shown[0] != null) shown[0].dismiss(); });
            finishPairing(pairingCancelled ? "Pairing cancelled." : "Pairing timed out. Try again.");
        } catch (Exception e) {
            runUi(() -> { if (shown[0] != null) shown[0].dismiss(); });
            finishPairing("Couldn’t reach your Mac. Keep Ascend open on the Mac and both devices on the same Wi-Fi.");
        }
    }
    void finishPairing(String message) { runUi(() -> { SyncEngine.RUNNING.set(false); toast(message); render(); }); }
    void forget() {
        dialog().setTitle("Forget " + engine.macName() + "?")
            .setMessage("This phone stops sending to that Mac until you pair again. Also choose Forget on the Mac (Health). Anything waiting stays on this phone.")
            .setPositiveButton("Forget", (d, w) -> {
                prefs.edit().remove("key").remove("macName").remove("service").putBoolean("backgroundSync", false).apply();
                SyncJob.schedule(this, false); toast("Forgotten. Pair again whenever you like."); render();
            })
            .setNegativeButton("Cancel", null).show();
    }

    // MARK: Photos
    void takePhoto() {
        captureName = UUID.randomUUID() + ".jpg";
        Uri uri = Uri.parse("content://" + PhotoProvider.AUTHORITY + "/capture/" + captureName);
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, uri)
            .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.setClipData(ClipData.newRawUri("", uri));
        try { startActivityForResult(intent, REQ_CAMERA); } catch (Exception e) { toast("No camera app is available."); }
    }
    void choosePhotos(int max) {
        Intent intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
        if (max > 1) intent.putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, Math.min(max, MediaStore.getPickImagesMaxLimit()));
        try { startActivityForResult(intent, REQ_PICK); } catch (Exception e) { toast("The photo picker isn’t available."); }
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == REQ_CAMERA) {
            File capture = captureName == null ? null : new File(new File(getFilesDir(), "capture"), captureName);
            captureName = null;
            if (result != RESULT_OK || capture == null || capture.length() == 0) { if (capture != null) capture.delete(); return; }
            long now = System.currentTimeMillis();
            if (photoMode.equals("med")) { network.execute(() -> importMedPhotos(List.of(() -> new FileInputStream(capture)), List.of(now), capture)); return; }
            askNote(note -> network.execute(() -> importMeal(() -> new FileInputStream(capture), now, note, capture)));
        } else if (request == REQ_PICK && result == RESULT_OK && data != null) {
            List<Uri> uris = new ArrayList<>();
            if (data.getClipData() != null) for (int i = 0; i < data.getClipData().getItemCount(); i++) uris.add(data.getClipData().getItemAt(i).getUri());
            else if (data.getData() != null) uris.add(data.getData());
            if (uris.isEmpty()) return;
            if (photoMode.equals("med")) {
                List<SyncEngine.Source> sources = new ArrayList<>(); List<Long> times = new ArrayList<>();
                for (Uri uri : uris) { sources.add(() -> getContentResolver().openInputStream(uri)); times.add(dateTaken(uri)); }
                network.execute(() -> importMedPhotos(sources, times, null)); return;
            }
            askNote(note -> { for (Uri uri : uris) { long taken = dateTaken(uri); network.execute(() -> importMeal(() -> getContentResolver().openInputStream(uri), taken, note, null)); } });
        }
    }
    void askNote(Consumer<String> done) {
        EditText field = new EditText(this);
        field.setHint("e.g. 2 rotis, dal (optional)"); field.setSingleLine(false); field.setTextColor(Ui.TEXT); field.setHintTextColor(Ui.FAINT);
        FrameLayout wrap = new FrameLayout(this); ui.pad(wrap, 20, 8, 20, 0); wrap.addView(field);
        dialog().setTitle("What’s in it?").setView(wrap)
            .setPositiveButton("Save", (d, w) -> done.accept(field.getText().toString().trim()))
            .setNegativeButton("Skip", (d, w) -> done.accept("")).setCancelable(false).show();
    }
    long dateTaken(Uri uri) {
        long now = System.currentTimeMillis();
        try (Cursor c = getContentResolver().query(uri, new String[]{MediaStore.MediaColumns.DATE_TAKEN}, null, null, null)) {
            if (c != null && c.moveToFirst() && !c.isNull(0)) { long taken = c.getLong(0); if (taken > 0) return Math.min(taken, now); }
        } catch (Exception ignored) {}
        return now;
    }
    void importMeal(SyncEngine.Source source, long takenAtMillis, String note, File cleanup) {
        try {
            String id = UUID.randomUUID().toString();
            SyncEngine.writeUpright(source, new File(engine.mealsDir(), id + ".jpg"));
            JSONObject meta = new JSONObject().put("id", id).put("takenAt", takenAtMillis / 1000).put("note", note.length() > 500 ? note.substring(0, 500) : note);
            try (FileOutputStream out = new FileOutputStream(new File(engine.mealsDir(), id + ".json"))) { out.write(SyncEngine.bytes(meta)); }
            if (cleanup != null) cleanup.delete();
            runUi(() -> { toast("Meal saved"); render(); sync(false, true); });
        } catch (Exception e) {
            if (cleanup != null) cleanup.delete();
            runUi(() -> toast("That photo couldn’t be read. Try another one."));
        }
    }
    /** Adds medicine photos to the open batch and returns to the batch screen. */
    void importMedPhotos(List<SyncEngine.Source> sources, List<Long> times, File cleanup) {
        int failed = 0;
        File batch = engine.openMedBatch();
        for (int i = 0; i < sources.size() && SyncEngine.json(batch).length < SyncEngine.MAX_MED_PHOTOS; i++) {
            try {
                String id = UUID.randomUUID().toString();
                SyncEngine.writeUpright(sources.get(i), new File(batch, id + ".jpg"));
                try (FileOutputStream out = new FileOutputStream(new File(batch, id + ".json"))) { out.write(SyncEngine.bytes(new JSONObject().put("id", id).put("takenAt", times.get(i) / 1000))); }
            } catch (Exception e) { failed++; }
        }
        if (cleanup != null) cleanup.delete();
        int skipped = failed;
        runUi(() -> { if (skipped > 0) toast(skipped == 1 ? "One photo couldn’t be read." : skipped + " photos couldn’t be read."); show(Screen.ADD_MEDS); });
    }
}
