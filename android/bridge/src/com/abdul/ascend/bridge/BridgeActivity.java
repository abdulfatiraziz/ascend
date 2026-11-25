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
    enum Screen { GOALS, TODAY, ROUTINE, HEALTH, BODY, SCREEN_TIME, MEALS, MEDS, URGES, NOTES, DOSSIER, SETTINGS, ADD_MEDS }
    /** The Mac's sidebar: Brief, Condition, Field log, Dossier, each with the same sub-tabs in the same order. */
    static final String[][] TABS = {{"Brief", "ic_brief"}, {"Condition", "ic_condition"}, {"Field log", "ic_fieldlog"}, {"Dossier", "ic_dossier"}};
    static final Screen[][] GROUPS = {{Screen.GOALS, Screen.TODAY, Screen.ROUTINE}, {Screen.HEALTH, Screen.BODY, Screen.SCREEN_TIME}, {Screen.MEALS, Screen.MEDS, Screen.URGES, Screen.NOTES}, {Screen.DOSSIER}};
    /** The last sub-tab opened in each tab, so a tab returns where you left it (like the Mac). */
    final Screen[] lastInTab = {Screen.TODAY, Screen.HEALTH, Screen.MEALS, Screen.DOSSIER};
    static int group(Screen s) { for (int g = 0; g < GROUPS.length; g++) for (Screen x : GROUPS[g]) if (x == s) return g; return -1; }
    static String subLabel(Screen s) { return s == Screen.SCREEN_TIME ? "Screen time" : s.name().charAt(0) + s.name().substring(1).toLowerCase(Locale.ROOT); }
    static final String LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK";
    static final int REQ_HEALTH = 7, REQ_NETWORK = 8, REQ_CAMERA = 11, REQ_PICK = 12, REQ_NOTIFY = 13, REQ_BACKGROUND = 14, REQ_LOCATION = 15, REQ_BACKGROUND_LOCATION = 16, REQ_SPOT_FINE = 17;
    static final String VERSION = "0.10.2";

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
        SpotReceiver.register(this);
        render();
        setRecentsScreenshotEnabled(!lockOnLeave());
        if (prefs.getBoolean("eyesOnly", false)) sealEyes(false);
        if ("com.abdul.ascend.bridge.EXERCISE_DEMOS".equals(getIntent().getAction())) openExerciseDemos();
    }

    // MARK: Eyes only
    EyesOnlyView eyes;
    /** True while the app itself opened the camera, photo picker or a Settings page, so coming back doesn't lock. */
    boolean ownTrip;
    boolean lockOnLeave() { return prefs.getBoolean("eyesLockOnLeave", true); }
    @Override public void startActivityForResult(Intent intent, int request, Bundle options) { ownTrip = true; super.startActivityForResult(intent, request, options); }
    @Override protected void onStart() { super.onStart(); ownTrip = false; }
    /** Leaving the app (home, switching apps, screen off) seals it, so it always opens on the vault. */
    @Override protected void onStop() {
        super.onStop();
        if (!isChangingConfigurations() && !ownTrip && lockOnLeave()) sealEyes(false);
    }
    /** Seals the app behind the vault, as on the Mac. It stays sealed after the app closes, until the fingerprint or PIN opens it. */
    void sealEyes() { sealEyes(true); }
    /** animated: the iris closes on screen; otherwise the vault is simply there (leaving the app, opening it sealed). */
    void sealEyes(boolean animated) {
        if (eyes != null) return;
        prefs.edit().putBoolean("eyesOnly", true).apply();
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);   // no preview in Recents, no screenshots of the data
        eyes = new EyesOnlyView(this, ui, this::askToOpen, this::openEyes);
        eyes.setElevation(ui.dp(60));
        root.addView(eyes, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        if (animated) eyes.post(eyes::seal); else eyes.sealedNow();
    }
    void openEyes() {
        if (eyes == null) return;
        prefs.edit().putBoolean("eyesOnly", false).apply();
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
        root.removeView(eyes); eyes = null;
    }
    /** The phone's own fingerprint sheet, with the PIN as the fallback. A phone with no screen lock just opens. */
    void askToOpen() {
        int how = android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG | android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL;
        if (getSystemService(android.hardware.biometrics.BiometricManager.class).canAuthenticate(how) != android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS) { if (eyes != null) eyes.cleared(); return; }
        new android.hardware.biometrics.BiometricPrompt.Builder(this).setTitle("Open Cipher").setSubtitle("Eyes only").setAllowedAuthenticators(how).build()
            .authenticate(new android.os.CancellationSignal(), getMainExecutor(), new android.hardware.biometrics.BiometricPrompt.AuthenticationCallback() {
                @Override public void onAuthenticationSucceeded(android.hardware.biometrics.BiometricPrompt.AuthenticationResult r) { if (eyes != null) eyes.cleared(); }
                @Override public void onAuthenticationFailed() { if (eyes != null) eyes.denied(); }
                @Override public void onAuthenticationError(int code, CharSequence msg) { if (eyes != null) eyes.cancelled(); }
            });
    }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); if ("com.abdul.ascend.bridge.EXERCISE_DEMOS".equals(intent.getAction())) openExerciseDemos(); }
    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putString("captureName", captureName); out.putString("photoMode", photoMode); out.putString("screen", screen.name());
    }
    @Override protected void onResume() { super.onResume(); if (engine!=null) SyncJob.schedule(this,false);render(); }
    /** Quietly syncs when the app comes to the front, at most every 10 minutes. */
    @Override public void onWindowFocusChanged(boolean focus) {
        super.onWindowFocusChanged(focus);
        if (focus && prefs.getBoolean("autoSync", true) && engine.paired() && !syncing
            && System.currentTimeMillis() - prefs.getLong("lastSync", 0) > 10 * 60 * 1000L) sync(true, true);
    }
    /**
     * Back returns to the previous screen and only leaves the app from Brief › Today. With predictive back (target SDK 36),
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

    void openExerciseDemos(){startActivity(new Intent(this,ExerciseDemoActivity.class));}
    void show(Screen s) { screen = s; int g = group(s); if (g >= 0) lastInTab[g] = s; render(); }
    /** The screen on display, so a refresh of the same screen (after a tap or a log) keeps where you had scrolled to. */
    Screen shown;
    /** A page waiting to be scrolled back, and to where. A tap re-renders twice in a row (the log, then the sync starting),
     *  and the second render must carry this position rather than read the not-yet-laid-out page's 0. */
    ScrollView restoring; int restoreY;
    static ScrollView firstScroll(View v) {
        if (v instanceof ScrollView) return (ScrollView) v;
        if (v instanceof ViewGroup) { ViewGroup g = (ViewGroup) v; for (int i = 0; i < g.getChildCount(); i++) { ScrollView s = firstScroll(g.getChildAt(i)); if (s != null) return s; } }
        return null;
    }
    void render() {
        if (root == null) return;
        ScrollView old = screen == shown && content.getChildCount() > 0 ? firstScroll(content.getChildAt(0)) : null;
        int keepY = old == null ? 0 : old == restoring ? restoreY : old.getScrollY();
        restoring = null;
        content.removeAllViews();
        View page;
        switch (screen) {
            case GOALS: page = goals(); break;
            case ROUTINE: page = routine(); break;
            case HEALTH: page = health(); break;
            case BODY: page = body(); break;
            case SCREEN_TIME: page = screenTime(); break;
            case MEALS: page = meals(); break;
            case MEDS: page = meds(); break;
            case URGES: page = urges(); break;
            case NOTES: page = notes(); break;
            case DOSSIER: page = dossier(); break;
            case SETTINGS: page = settings(); break;
            case ADD_MEDS: page = addMeds(); break;
            default: page = today();
        }
        content.addView(page, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        shown = screen;
        ScrollView fresh = keepY > 0 ? firstScroll(page) : null;
        if (fresh != null) {
            // Restore once the new page is laid out; before that the scroll range is zero and the position would be lost.
            restoring = fresh; restoreY = keepY;
            fresh.getViewTreeObserver().addOnGlobalLayoutListener(new android.view.ViewTreeObserver.OnGlobalLayoutListener() {
                @Override public void onGlobalLayout() {
                    fresh.getViewTreeObserver().removeOnGlobalLayoutListener(this);
                    if (restoring != fresh) return;
                    fresh.scrollTo(0, keepY); restoring = null;
                }
            });
        }
        boolean tabs = group(screen) >= 0;
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
        String[][] tabs = TABS;
        int current = group(screen);
        for (int i = 0; i < tabs.length; i++) {
            boolean on = current == i;
            LinearLayout tab = ui.column(4); tab.setGravity(Gravity.CENTER_HORIZONTAL);
            FrameLayout pill = new FrameLayout(this);
            if (on) pill.setBackground(ui.round(0x2ED9B46E, 15, 0, 0));
            pill.addView(ui.iconView(tabs[i][1], on ? Ui.ACCENT : Ui.MUTED, 22), new FrameLayout.LayoutParams(ui.dp(22), ui.dp(22), Gravity.CENTER));
            tab.addView(pill, new LinearLayout.LayoutParams(ui.dp(56), ui.dp(30)));
            // Column children are full width, so the label itself must be centred under the icon.
            TextView label = ui.text(tabs[i][0], 11, on ? Ui.ACCENT : Ui.MUTED, on ? 600 : 500); label.setGravity(Gravity.CENTER);
            tab.addView(label);
            int index = i;
            tab.setOnClickListener(Ui.tap(v -> show(lastInTab[index])));
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
        card.setBackground(ui.round(Ui.PANEL, 18, 0x59D9B46E, 1));
        card.addView(ui.text("Connect to your Mac", 17, Ui.TEXT, 600));
        card.addView(ui.body("1. On the Mac, open Cipher → Health → Pair phone.\n2. Tap Pair with Mac and check the 6-digit code matches.\n3. Choose which health data to share."));
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
        card.setBackground(ui.round(Ui.PANEL, 18, 0x59D9B46E, 1));
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
        col.addView(tabHead());
        View snap = ui.iconButton("Take meal photo", "ic_camera", ui.round(Ui.ACCENT, 16, 0, 0), Ui.ON_ACCENT, 56, v -> { photoMode = "meal"; takePhoto(); });
        View pick = ui.iconButton("Choose from gallery", "ic_gallery", ui.round(Ui.PANEL, 14, 0x1FFFFFFF, 1), Ui.TEXT, 48, v -> { photoMode = "meal"; choosePhotos(SyncEngine.MAX_MEAL_PHOTOS); });
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
        List<String> photos = new ArrayList<>();
        boolean open = false;
        try {
            JSONObject m = SyncEngine.readJSON(meta);
            note = m.optString("note"); time = clock(m.optLong("takenAt") * 1000); open = m.optBoolean("open");
            photos = SyncEngine.mealPhotos(m);
        } catch (Exception ignored) {}
        File first = photos.isEmpty() ? null : new File(engine.mealsDir(), photos.get(0) + ".jpg");
        card.addView(thumb(first), new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(104)));
        LinearLayout text = ui.column(2); ui.pad(text, 12, 10, 12, 10);
        text.addView(ui.oneLine(ui.text(open ? "Tap to finish" : note.isEmpty() ? "No note" : note, 13, open ? Ui.ACCENT_TEXT : note.isEmpty() ? Ui.MUTED : Ui.TEXT, 500)));
        text.addView(ui.mono(time + (photos.size() > 1 ? " · " + photos.size() + " photos" : ""), 11, Ui.MUTED));
        card.addView(text);
        List<String> photoIds = photos;
        if (open) card.setOnClickListener(Ui.tap(v -> askMealNote(meta)));
        card.setOnLongClickListener(v -> {
            dialog().setTitle(photoIds.size() > 1 ? "Remove this meal and its " + photoIds.size() + " photos?" : "Remove this meal photo?").setMessage("It hasn’t been sent yet.")
                .setPositiveButton("Remove", (d, w) -> { for (String id : photoIds) new File(engine.mealsDir(), id + ".jpg").delete(); meta.delete(); render(); })
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
        col.addView(tabHead()); col.addView(pill);
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
        col.addView(ui.iconButton("Add medicines with photos", "ic_plus", ui.dashed(Ui.PANEL, 16, 0x8CD9B46E), Ui.ACCENT_TEXT, 52, v -> show(Screen.ADD_MEDS)), Ui.wide());
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
        tile.setBackground(accent ? ui.round(Ui.ACCENT_SOFT, 16, 0x99D9B46E, 1.5f) : ui.round(Ui.PANEL, 16, 0x1FFFFFFF, 1));
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
    /** Field log › Urges. Spot visits come first, waiting for a yes or no; then the counts; then every recent urge and whether it reached the Mac. */
    View urges() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        col.addView(syncPill(), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
        List<UrgeRow> rows = urgeRows();
        List<UrgeRow> open = new ArrayList<>();
        for (UrgeRow r : rows) if (r.visit()) open.add(r);

        LinearLayout ask = ui.card(12);
        LinearLayout head = ui.row(8);
        head.addView(ui.kicker("To approve"), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (!open.isEmpty()) head.addView(ui.mono(open.size() + (open.size() == 1 ? " visit" : " visits"), 12, Ui.ACCENT_TEXT));
        ask.addView(head);
        if (open.isEmpty()) ask.addView(ui.small("Nothing waiting. When you arrive at a saved spot, Cipher asks once; if you don't answer then, the visit waits here."));
        for (UrgeRow r : open) {
            LinearLayout item = ui.column(10);
            item.setBackground(ui.round(Ui.PANEL2, 16, Ui.LINE, 1)); ui.pad(item, 14, 14, 14, 14);
            LinearLayout top = ui.row(10);
            top.addView(ui.badge("ic_urge", Ui.ACCENT_SOFT, Ui.ACCENT, 34, 18));
            LinearLayout words = ui.column(2);
            words.addView(ui.oneLine(ui.text("Arrived at " + (r.spot == null ? "a spot" : r.spot), 16, Ui.TEXT, 600)));
            words.addView(ui.small(dayLabel(r.at) + " · " + clock12(r.at) + " · " + syncLabel(r)));
            top.addView(words, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            item.addView(top);
            LinearLayout buttons = ui.row(10);
            buttons.addView(ui.pill("Let it pass", v -> approveVisit(r, "Let it pass")), new LinearLayout.LayoutParams(0, ui.dp(44), 1));
            buttons.addView(ui.outline("Acted on it", v -> approveVisit(r, "Acted on it")), new LinearLayout.LayoutParams(0, ui.dp(44), 1));
            item.addView(buttons);
            ask.addView(item);
        }
        col.addView(ask);

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

        if (!rows.isEmpty()) {
            LinearLayout recent = ui.card(0);
            LinearLayout rh = ui.row(8);
            rh.addView(ui.kicker("Recent"), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            int waiting = engine.queuedUrges().length;
            rh.addView(ui.mono(waiting > 0 ? waiting + " to send" : macList() != null ? "all on your Mac" : "", 12, waiting > 0 ? Ui.ACCENT_TEXT : Ui.GREEN));
            recent.addView(rh);
            for (int i = 0; i < Math.min(rows.size(), 12); i++) {
                UrgeRow r = rows.get(i);
                LinearLayout row = ui.row(12); ui.pad(row, 0, 12, 0, 12);
                row.addView(ui.mono(clock12(r.at), 13, Ui.MUTED), new LinearLayout.LayoutParams(ui.dp(66), Ui.WRAP));
                LinearLayout words = ui.column(2);
                boolean acted = "Acted on it".equals(r.outcome);
                String what = r.visit() ? "Visit, not answered yet" : "Not recorded".equals(r.outcome) ? "No outcome" : r.outcome;
                words.addView(ui.text(what, 14, acted ? Ui.ORANGE : r.visit() ? Ui.MUTED : Ui.TEXT, r.visit() ? 400 : 500));
                String where = r.spot != null ? r.spot : r.trigger != null ? r.trigger : "";
                words.addView(ui.small(dayLabel(r.at) + (where.isEmpty() ? "" : " · " + where)));
                row.addView(words, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                row.addView(syncTag(r));
                if (i > 0) { View rule = new View(this); rule.setBackgroundColor(Ui.LINE); recent.addView(rule, new LinearLayout.LayoutParams(Ui.MATCH, 1)); }
                recent.addView(row);
            }
            col.addView(recent);
        }
        col.addView(ui.secondary("Log an urge yourself", v -> logUrge(null)));
        return holder[0];
    }

    /** One urge as the phone knows it: the Mac's copy, updated by anything this phone still has waiting to send. */
    static final class UrgeRow {
        String id, outcome, spot, trigger; long at; boolean onMac, waiting;
        boolean visit() { return spot != null && "Not recorded".equals(outcome); }
    }
    /** The Mac's urges from its last reply (8 days), or null before a Mac that sends them has synced. */
    JSONArray macList() { JSONObject b = engine.today().optJSONObject("brief"); return b == null ? null : b.optJSONArray("urges"); }
    List<UrgeRow> urgeRows() {
        Map<String, UrgeRow> byID = new LinkedHashMap<>();
        JSONArray mac = macList();
        if (mac != null) for (int i = 0; i < mac.length(); i++) {
            JSONObject u = mac.optJSONObject(i); if (u == null) continue;
            UrgeRow r = new UrgeRow();
            r.id = u.optString("id").toLowerCase(Locale.ROOT); r.at = (long) (u.optDouble("at") * 1000); r.outcome = u.optString("outcome");
            r.spot = u.isNull("spot") || u.optString("spot").isEmpty() ? null : u.optString("spot");
            r.trigger = u.isNull("trigger") || u.optString("trigger").isEmpty() ? null : u.optString("trigger");
            r.onMac = true; byID.put(r.id, r);
        }
        for (File f : engine.queuedUrges()) {
            try {
                JSONObject u = SyncEngine.readJSON(f);
                String id = u.optString("id").toLowerCase(Locale.ROOT);
                UrgeRow r = byID.containsKey(id) ? byID.get(id) : new UrgeRow();
                r.id = id; r.at = u.optLong("takenAt") * 1000; r.outcome = u.optString("outcome", "Not recorded");
                if (u.has("spot") && !u.optString("spot").isEmpty()) r.spot = u.optString("spot");
                if (u.has("trigger") && !u.optString("trigger").isEmpty()) r.trigger = u.optString("trigger");
                r.waiting = true; byID.put(id, r);
            } catch (Exception ignored) {}
        }
        List<UrgeRow> rows = new ArrayList<>(byID.values());
        if (mac == null) {
            // Before the Mac sends its list: what this phone logged, without IDs, so no sync state to show.
            JSONArray h = urgeHistory();
            for (int i = 0; i < h.length(); i++) {
                JSONObject e = h.optJSONObject(i); if (e == null) continue;
                UrgeRow r = new UrgeRow(); r.at = e.optLong("at"); r.outcome = e.optString("outcome");
                boolean dup = false;
                for (UrgeRow q : rows) if (Math.abs(q.at - r.at) < 60000 && q.outcome.equals(r.outcome)) dup = true;
                if (!dup) rows.add(r);
            }
        }
        rows.sort((a, b) -> Long.compare(b.at, a.at));
        return rows;
    }
    String syncLabel(UrgeRow r) { return r.waiting ? "waiting to send" : r.onMac ? "on your Mac" : "on this phone"; }
    View syncTag(UrgeRow r) {
        LinearLayout tag = ui.row(6);
        int color = r.waiting ? Ui.ACCENT : r.onMac ? Ui.GREEN : Ui.FAINT;
        View dot = new View(this); dot.setBackground(ui.round(color, 3, 0, 0));
        tag.addView(dot, new LinearLayout.LayoutParams(ui.dp(6), ui.dp(6)));
        tag.addView(ui.text(r.waiting ? "To send" : r.onMac ? "On Mac" : r.id == null ? "Phone" : "—", 12, r.waiting ? Ui.ACCENT_TEXT : r.onMac ? Ui.GREEN : Ui.FAINT, 500));
        return tag;
    }
    static String dayLabel(long millis) {
        LocalDate day = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate(), now = LocalDate.now();
        if (day.equals(now)) return "Today";
        if (day.equals(now.minusDays(1))) return "Yesterday";
        return day.getDayOfWeek().getDisplayName(java.time.format.TextStyle.SHORT, Locale.ENGLISH) + " " + day.getDayOfMonth();
    }
    /** Answers a spot visit. Same ID as the visit, so the Mac turns its unanswered visit into this outcome; nothing new is logged. */
    void approveVisit(UrgeRow r, String outcome) {
        try {
            File f = new File(engine.urgesDir(), r.id + ".json");
            if (f.exists() || prefs.contains("visit|" + r.id)) SpotReceiver.answer(this, r.id, outcome);
            else {
                JSONObject u = new JSONObject().put("id", r.id).put("takenAt", r.at / 1000).put("outcome", outcome).put("note", "");
                if (r.spot != null) u.put("spot", r.spot);
                writeJSON(f, u);
                getSystemService(android.app.NotificationManager.class).cancel(r.id.hashCode());
                JSONArray history = urgeHistory(), next = new JSONArray().put(new JSONObject().put("at", r.at).put("outcome", outcome));
                for (int i = 0; i < Math.min(history.length(), 19); i++) next.put(history.get(i));
                prefs.edit().putString("urgeHistory", next.toString()).apply();
            }
            toast(outcome.equals("Let it pass") ? "Let it pass · saved" : "Acted on it · saved");
        } catch (Exception e) { toast("Couldn't save that answer."); }
        render();
        sync(false, true);
    }
    JSONArray urgeHistory() { try { return new JSONArray(prefs.getString("urgeHistory", "[]")); } catch (JSONException e) { return new JSONArray(); } }
    void styleChip(Button b, boolean on) {
        b.setBackground(on ? ui.round(Ui.ACCENT_SOFT, 18, Ui.ACCENT, 1) : ui.round(Ui.PANEL2, 18, 0, 0));
        b.setTextColor(on ? Ui.LAMP : Ui.TEXT);
    }

    // MARK: Log (home)
    static final String[][] URGE_TRIGGERS = {{"Need quiet", "Work break", "Bored"}, {"After a meal", "Stress", "Noise"}, {"Going out anyway", "With people"}};
    static final String FINE = android.Manifest.permission.ACCESS_FINE_LOCATION, COARSE = android.Manifest.permission.ACCESS_COARSE_LOCATION;
    File pendingLocation;
    final Set<String> locating = new HashSet<>();

    static String clock12(long millis) {
        LocalTime t = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalTime();
        int h = t.getHour();
        return (h % 12 == 0 ? 12 : h % 12) + ":" + String.format(Locale.ROOT, "%02d", t.getMinute()) + (h < 12 ? " am" : " pm");
    }
    /** Today's cached summary from the Mac, or empty when it's from an earlier day. */
    JSONObject todayFresh() {
        JSONObject t = engine.today();
        return LocalDate.now().toString().equals(t.optString("day")) ? t : new JSONObject();
    }
    /** Brief › Today, laid out like the Mac's Today: the lede, your taps, what Ascend tracks itself, then the missions. */
    View today() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        JSONObject t = todayFresh();
        JSONObject b = t.optJSONObject("brief");
        col.addView(tabHead());
        col.addView(syncPill(), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
        if (!engine.paired()) col.addView(setupCard());
        if (b != null && !b.optString("focus").isEmpty()) {
            LinearLayout f = ui.column(4);
            f.addView(serif(b.optString("focus"), 23));
            String d = b.optString("focusDetail");
            if (!d.isEmpty()) f.addView(ui.small(d));
            col.addView(f);
        }
        JSONObject daily = b == null ? null : b.optJSONObject("dailyMemo");
        if (daily != null) col.addView(dailyMemoCard(daily, b.optString("dailyMemoDate")));
        // Phone-only: the one-tap logs. Weight, steps, sleep and screen time arrive on their own; urges come from spot visits (Field log › Urges).
        col.addView(ui.grid(8,
            logTile("ic_meal", "Meal", false, v -> { photoMode = "meal"; takePhoto(); }),
            logTile("ic_pill", "Meds", false, v -> show(Screen.MEDS)),
            logTile("ic_dumbbell", "Workout", false, v -> show(Screen.BODY))));
        if (t.length() > 0) col.addView(foodCard(t, b == null ? null : b.optJSONObject("food")));
        col.addView(tapsCard(t));
        if (b != null && b.optJSONArray("tracking") != null) col.addView(trackingCard(b));
        if (b != null && b.optJSONArray("missions") != null) col.addView(missionStrip(b.optJSONArray("missions")));
        int waiting = engine.waiting();
        TextView w = ui.small(waiting == 0 ? "Nothing waiting to send" : waiting + (waiting == 1 ? " item" : " items") + " waiting · sent on the next sync");
        w.setGravity(Gravity.CENTER); col.addView(w);
        askNotificationsOnce();
        return holder[0];
    }
    /** What you ate today: calories against the limit, then protein, carbs and fat, then each meal. Confirmed meals only count. */
    View foodCard(JSONObject t, JSONObject food) {
        double kcal = food != null ? food.optDouble("kcal", 0) : t.optDouble("kcal", 0);
        double protein = food != null ? food.optDouble("protein", 0) : t.optDouble("protein", 0);
        double limit = food != null ? food.optDouble("kcalLimit", Double.NaN) : t.optDouble("kcalLimit", Double.NaN);
        double goal = food != null ? food.optDouble("proteinGoal", Double.NaN) : t.optDouble("proteinGoal", Double.NaN);
        LinearLayout card = ui.card(10);
        LinearLayout head = ui.row(8); head.setGravity(Gravity.BOTTOM);
        TextView k = ui.kicker("Eaten today"); k.setTextColor(Ui.ACCENT);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        boolean over = !Double.isNaN(limit) && kcal > limit;
        if (!Double.isNaN(limit)) head.addView(ui.mono(over ? fmt(kcal - limit) + " over" : fmt(limit - kcal) + " left", 12, over ? Ui.ORANGE : Ui.MUTED));
        card.addView(head);
        LinearLayout v = ui.row(6); v.setGravity(Gravity.BOTTOM);
        TextView big = serif(fmt(kcal), 34); if (over) big.setTextColor(Ui.ORANGE); v.addView(big);
        v.addView(ui.text(Double.isNaN(limit) ? "kcal" : "/ " + fmt(limit) + " kcal", 13, Ui.MUTED, 500));
        card.addView(v);
        if (!Double.isNaN(limit)) card.addView(ui.bar(kcal / limit, over ? Ui.ORANGE : Ui.ACCENT));
        boolean macros = food != null;
        card.addView(ui.grid(8,
            macro("Protein", protein, Double.isNaN(goal) ? "" : "/" + fmt(goal), Double.isNaN(goal) ? Double.NaN : protein / goal),
            macro("Carbs", macros ? food.optDouble("carbs", 0) : Double.NaN, "", Double.NaN),
            macro("Fat", macros ? food.optDouble("fat", 0) : Double.NaN, "", Double.NaN)));
        JSONArray meals = food == null ? null : food.optJSONArray("meals");
        if (meals != null && meals.length() > 0) {
            card.addView(ui.divider());
            for (int i = 0; i < meals.length(); i++) {
                JSONObject m = meals.optJSONObject(i);
                LinearLayout row = ui.row(10); row.setGravity(Gravity.CENTER_VERTICAL); ui.pad(row, 0, 4, 0, 4);
                row.addView(ui.mono(m.optString("time"), 11, Ui.MUTED), new LinearLayout.LayoutParams(ui.dp(62), Ui.WRAP));
                row.addView(ui.oneLine(ui.text(m.optString("title"), 14, Ui.TEXT, 500)), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                row.addView(m.optBoolean("confirmed")
                    ? ui.mono(fmt(m.optDouble("kcal")) + " kcal · " + fmt(m.optDouble("protein")) + "P " + fmt(m.optDouble("carbs")) + "C " + fmt(m.optDouble("fat")) + "F", 11, Ui.MUTED)
                    : ui.mono("ESTIMATING", 10, Ui.ORANGE));
                card.addView(row);
            }
        } else card.addView(ui.small(food == null ? "Sync to see carbs, fat and each meal." : "No meals logged yet. Tap Meal above to photo one."));
        int pending = food == null ? 0 : food.optInt("pending");
        if (pending > 0) card.addView(ui.small(pending + (pending == 1 ? " meal" : " meals") + " still estimating on the Mac · not counted yet"));
        card.setOnClickListener(Ui.tap(x -> show(Screen.MEALS)));
        return card;
    }
    View macro(String label, double grams, String of, double fraction) {
        LinearLayout c = ui.column(4); c.setBackground(ui.round(Ui.PANEL2, 14, 0, 0)); ui.pad(c, 12, 10, 12, 10);
        c.addView(ui.kicker(label));
        LinearLayout v = ui.row(3); v.setGravity(Gravity.BOTTOM);
        v.addView(ui.text(Double.isNaN(grams) ? "—" : fmt(grams) + " g", 16, Ui.TEXT, 700));
        if (!of.isEmpty()) v.addView(ui.oneLine(ui.text(of, 11, Ui.MUTED, 500)));
        c.addView(v);
        if (!Double.isNaN(fraction)) c.addView(ui.bar(fraction, fraction >= 1 ? Ui.GREEN : Ui.ACCENT));
        return c;
    }
    /** The Mac's "Your taps": doses still due, then the check-ins only you can answer. */
    View tapsCard(JSONObject t) {
        LinearLayout card = ui.card(10);
        // Like the Mac: one per medicine time still open, plus each check-in not answered.
        java.util.Set<Integer> openTimes = new java.util.HashSet<>();
        for (JSONObject d : dosesToday()) if (!ReminderReceiver.taken(this, d)) openTimes.add(d.optInt("minute"));
        int left = openTimes.size();
        JSONArray habits = t.optJSONArray("habits");
        for (int i = 0; habits != null && i < habits.length(); i++) { JSONObject h = habits.optJSONObject(i); if (h != null && !h.optBoolean("auto") && !h.optBoolean("done")) left++; }
        LinearLayout head = ui.row(8); head.setGravity(Gravity.CENTER_VERTICAL);
        TextView k = ui.kicker("Your taps"); k.setTextColor(Ui.ACCENT);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        head.addView(ui.text(left == 0 ? "All done" : left + " left today", 12, left == 0 ? Ui.GREEN : Ui.MUTED, 500));
        card.addView(head);
        if (t.optBoolean("rest")) card.addView(ui.small("Rest day · check-ins kept, not scored"));
        JSONObject next = nextDose();
        if (next != null) card.addView(nextDoseCard(next));
        String period = null; int shown = 0;
        for (int i = 0; habits != null && i < habits.length(); i++) {
            JSONObject h = habits.optJSONObject(i);
            if (h == null || h.optBoolean("auto")) continue;
            if (!h.optString("period").equals(period)) {
                period = h.optString("period");
                TextView p = ui.kicker(period); p.setPadding(0, ui.dp(shown == 0 ? 2 : 10), 0, 0); card.addView(p);
            }
            card.addView(habitRow(h, t.optString("day")));
            shown++;
        }
        if (shown == 0 && next == null) card.addView(ui.small("Nothing to tap right now."));
        return card;
    }
    /** The Mac's "Ascend is tracking": filled by the watch, the phone and your meals. Nothing to tap. */
    View trackingCard(JSONObject b) {
        LinearLayout card = ui.card(0);
        LinearLayout head = ui.row(8); head.setGravity(Gravity.CENTER_VERTICAL); ui.pad(head, 0, 0, 0, 6);
        TextView k = ui.kicker("Cipher is tracking"); k.setTextColor(Ui.ACCENT);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        head.addView(ui.text("Nothing to tap here", 12, Ui.MUTED, 500));
        card.addView(head);
        JSONArray lines = b.optJSONArray("tracking");
        for (int i = 0; i < lines.length(); i++) {
            JSONObject l = lines.optJSONObject(i);
            if (i > 0) card.addView(ui.divider());
            String st = l.optString("state");
            int color = st.equals("done") ? Ui.GREEN : st.equals("missed") ? Ui.RED : st.equals("going") ? Ui.ACCENT : Ui.FAINT;
            LinearLayout row = ui.row(12); row.setGravity(Gravity.CENTER_VERTICAL); ui.pad(row, 0, 10, 0, 10);
            View dot = new View(this); dot.setBackground(st.equals("waiting") ? ui.round(0, 5, color, 1.5f) : ui.round(color, 5, 0, 0));
            row.addView(dot, new LinearLayout.LayoutParams(ui.dp(10), ui.dp(10)));
            LinearLayout text = ui.column(3);
            LinearLayout top = ui.row(8);
            top.addView(ui.oneLine(ui.text(l.optString("title"), 15, Ui.TEXT, 500)), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            top.addView(ui.mono(l.optString("value"), 12, st.equals("missed") ? Ui.RED : Ui.SOFT));
            text.addView(top);
            if (l.has("ratio") && !l.isNull("ratio")) text.addView(ui.bar(l.optDouble("ratio"), color));
            if (l.has("note") && !l.isNull("note") && !l.optString("note").isEmpty()) text.addView(ui.small(l.optString("note")));
            row.addView(text, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            if (l.optString("title").equals("Urges")) row.setOnClickListener(Ui.tap(x -> show(Screen.URGES)));
            card.addView(row);
        }
        JSONObject s = b.optJSONObject("score");
        if (s != null) {
            card.addView(ui.divider());
            LinearLayout row = ui.row(10); row.setGravity(Gravity.CENTER_VERTICAL); ui.pad(row, 0, 12, 0, 0);
            row.addView(serif(s.optInt("completed") + " / " + s.optInt("scheduled"), 24));
            row.addView(ui.small(s.optString("line")), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            card.addView(row);
        }
        return card;
    }
    /** The Mac's mission strip under Today; tap to open Goals. */
    View missionStrip(JSONArray ms) {
        HorizontalScrollView scroll = new HorizontalScrollView(this); scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout strip = ui.row(8);
        for (int i = 0; i < ms.length(); i++) {
            JSONObject m = ms.optJSONObject(i);
            LinearLayout chip = ui.column(6); chip.setBackground(ui.round(Ui.PANEL, 14, Ui.LINE, 1)); ui.pad(chip, 12, 10, 12, 10);
            LinearLayout top = ui.row(8); top.setGravity(Gravity.CENTER_VERTICAL);
            TextView letter = serif(m.optString("id"), 20); letter.setTextColor(Ui.ACCENT_TEXT); top.addView(letter);
            top.addView(ui.oneLine(ui.text(m.optString("title"), 13, Ui.TEXT, 500)), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            top.addView(ui.mono(Math.round(m.optDouble("progress") * 100) + "%", 11, Ui.MUTED));
            chip.addView(top);
            chip.addView(ui.bar(Math.max(0.01, m.optDouble("progress")), m.optString("status").equals("On plan") ? Ui.GREEN : Ui.ACCENT));
            chip.setOnClickListener(Ui.tap(x -> show(Screen.GOALS)));
            strip.addView(chip, new LinearLayout.LayoutParams(ui.dp(176), Ui.WRAP));
        }
        scroll.addView(strip);
        return scroll;
    }
    View logTile(String icon, String label, boolean hot, View.OnClickListener l) {
        LinearLayout tile = ui.column(6); tile.setGravity(Gravity.CENTER);
        tile.setBackground(hot ? ui.round(0x14E6B04E, 16, 0x73E6B04E, 1) : ui.round(Ui.PANEL, 16, Ui.LINE, 1));
        tile.addView(ui.iconView(icon, hot ? Ui.ORANGE : Ui.ACCENT_TEXT, 22));
        TextView text = ui.oneLine(ui.text(label, 12, Ui.TEXT, 500)); text.setGravity(Gravity.CENTER);
        tile.addView(text);
        tile.setMinimumHeight(ui.dp(78)); tile.setContentDescription(label);
        tile.setOnClickListener(Ui.tap(l));
        return tile;
    }
    JSONArray logHistory() { try { return new JSONArray(prefs.getString("logHistory", "[]")); } catch (JSONException e) { return new JSONArray(); } }
    void addHistory(String label, String tag) {
        try {
            JSONArray old = logHistory(), next = new JSONArray().put(new JSONObject().put("at", System.currentTimeMillis()).put("label", label).put("tag", tag));
            for (int i = 0; i < Math.min(old.length(), 79); i++) next.put(old.get(i));
            prefs.edit().putString("logHistory", next.toString()).apply();
        } catch (JSONException ignored) {}
    }
    static void writeJSON(File file, JSONObject json) throws IOException { try (OutputStream out = new FileOutputStream(file)) { out.write(SyncEngine.bytes(json)); } }

    // MARK: Urge
    void bumpActed(int delta) {
        try {
            JSONObject t = engine.today();
            if (!LocalDate.now().toString().equals(t.optString("day"))) return;
            t.put("urgesActedToday", Math.max(0, t.optInt("urgesActedToday") + delta));
            engine.saveToday(t);
        } catch (JSONException ignored) {}
    }
    /** Opens the urge sheet. Nothing is saved until an outcome is picked and Save is tapped; Cancel leaves no trace. */
    void logUrge(String outcome) {
        long now = System.currentTimeMillis();
        File file = new File(engine.urgesDir(), UUID.randomUUID() + ".json");
        // Warm up a location fix now so Save can attach it quickly.
        if (prefs.getBoolean("urgeLocation", true) && (checkSelfPermission(FINE) == PackageManager.PERMISSION_GRANTED || checkSelfPermission(COARSE) == PackageManager.PERMISSION_GRANTED))
            currentLocation(loc -> {}, "warm-" + file.getName());
        urgeSheet(file, now, outcome);
    }
    void captureLocation(File file) {
        if (checkSelfPermission(FINE) != PackageManager.PERMISSION_GRANTED && checkSelfPermission(COARSE) != PackageManager.PERMISSION_GRANTED) {
            if (prefs.getBoolean("askedLocation", false)) return;
            prefs.edit().putBoolean("askedLocation", true).apply();
            pendingLocation = file;
            requestPermissions(new String[]{FINE, COARSE}, REQ_LOCATION);
            return;
        }
        currentLocation(loc -> {
            if (loc == null || !file.exists()) return;
            try {
                JSONObject u = SyncEngine.readJSON(file);
                if (!u.optBoolean("noLocation")) { u.put("latitude", loc.getLatitude()).put("longitude", loc.getLongitude()); writeJSON(file, u); }
            } catch (Exception ignored) {}
        }, file.getName());
    }
    /** A recent fix if there is one, else a fresh one; null when none arrives. `tag` marks the request as in flight. */
    void currentLocation(Consumer<android.location.Location> done, String tag) {
        android.location.LocationManager lm = getSystemService(android.location.LocationManager.class);
        List<String> providers = lm.getProviders(true);
        String provider = providers.contains("fused") ? "fused" : providers.contains("network") ? "network" : providers.contains("gps") ? "gps" : null;
        if (provider == null) { done.accept(null); return; }
        try {
            android.location.Location last = lm.getLastKnownLocation(provider);
            if (last != null && System.currentTimeMillis() - last.getTime() < 2 * 60 * 1000L) { done.accept(last); return; }
            locating.add(tag);
            lm.getCurrentLocation(provider, null, getMainExecutor(), loc -> { locating.remove(tag); done.accept(loc); });
            main.postDelayed(() -> locating.remove(tag), 15000);
        } catch (SecurityException e) { locating.remove(tag); done.accept(null); }
    }
    void urgeSheet(File file, long at, String preset) {
        Dialog sheet = new Dialog(this);
        sheet.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout box = ui.column(14);
        GradientDrawable bg = new GradientDrawable(); bg.setColor(Ui.PANEL);
        float r = ui.dp(24); bg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        box.setBackground(bg); box.setPadding(ui.dp(20), ui.dp(12), ui.dp(20), insetBottom + ui.dp(20));
        View handle = new View(this); handle.setBackground(ui.round(0x33FFFFFF, 2, 0, 0));
        LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(ui.dp(40), ui.dp(4)); hp.gravity = Gravity.CENTER_HORIZONTAL;
        box.addView(handle, hp);
        LinearLayout head = ui.row(12);
        head.addView(ui.badge("ic_urge", Ui.ACCENT_SOFT, Ui.ACCENT, 40, 20));
        LinearLayout titles = ui.column(2);
        titles.addView(ui.text("Urge", 20, Ui.TEXT, 700));
        titles.addView(ui.small(clock12(at) + " · pick one, then Save"));
        head.addView(titles);
        box.addView(head);
        String[] outcome = {preset};
        LinearLayout seg = ui.grid(8);
        Button acted = ui.chip("Acted on it", "Acted on it".equals(preset), v -> {}), passed = ui.chip("Let it pass", "Let it pass".equals(preset), v -> {});
        acted.setOnClickListener(Ui.tap(v -> { outcome[0] = "Acted on it"; styleChip(acted, true); styleChip(passed, false); }));
        passed.setOnClickListener(Ui.tap(v -> { outcome[0] = "Let it pass"; styleChip(acted, false); styleChip(passed, true); }));
        seg.addView(acted, new LinearLayout.LayoutParams(0, ui.dp(42), 1)); seg.addView(passed, new LinearLayout.LayoutParams(0, ui.dp(42), 1));
        box.addView(seg);
        box.addView(ui.text("How strong?", 12, Ui.MUTED, 600));
        int[] intensity = {0};
        LinearLayout levels = ui.row(8);
        Button[] levelButtons = new Button[5];
        for (int i = 1; i <= 5; i++) {
            int level = i;
            Button b = ui.chip(String.valueOf(i), false, v -> {});
            b.setOnClickListener(Ui.tap(v -> { intensity[0] = intensity[0] == level ? 0 : level; for (int k = 0; k < 5; k++) styleChip(levelButtons[k], intensity[0] == k + 1); }));
            levelButtons[i - 1] = b;
            levels.addView(b, new LinearLayout.LayoutParams(0, ui.dp(40), 1));
        }
        box.addView(levels);
        box.addView(ui.text("What started it?", 12, Ui.MUTED, 600));
        String[] trigger = {null};
        List<Button> chips = new ArrayList<>();
        List<String> names = new ArrayList<>();
        LinearLayout lines = ui.column(8);
        for (String[] rowNames : URGE_TRIGGERS) {
            LinearLayout line = ui.row(8);
            for (String name : rowNames) {
                Button b = ui.chip(name, false, v -> {});
                chips.add(b); names.add(name);
                b.setOnClickListener(Ui.tap(v -> {
                    trigger[0] = name.equals(trigger[0]) ? null : name;
                    for (int k = 0; k < chips.size(); k++) styleChip(chips.get(k), names.get(k).equals(trigger[0]));
                }));
                line.addView(b, new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
            }
            lines.addView(line);
        }
        box.addView(lines);
        boolean[] early = {false}, anchor = {false}, place = {prefs.getBoolean("urgeLocation", true)}, touched = {false};
        box.addView(toggle("Caught the first thought?", "Before it grew into a plan", false, on -> { early[0] = on; touched[0] = true; }));
        box.addView(toggle("Used my anchor", "Your interrupt technique, as soon as you noticed", false, on -> { anchor[0] = on; touched[0] = true; }));
        box.addView(toggle("Save location", "Kept on this phone and your Mac only", place[0], on -> { place[0] = on; prefs.edit().putBoolean("urgeLocation", on).apply(); }));
        box.addView(ui.secondary("Save this place as a spot", v -> saveSpotHere(file)), Ui.wide());
        JSONObject t = todayFresh();
        if (t.has("urgesActedToday")) {
            double avg = t.optDouble("urgesActedWeekAverage", Double.NaN);
            box.addView(ui.small("Acted on today: " + t.optInt("urgesActedToday") + (Double.isNaN(avg) ? "" : " · 7-day average " + fmt(avg))));
        }
        LinearLayout buttons = ui.row(10);
        boolean[] saved = {false};
        buttons.addView(ui.secondary("Cancel", v -> sheet.dismiss()), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(52)));
        buttons.addView(ui.primary("Save", v -> {
            if (outcome[0] == null) { toast("Pick Acted on it or Let it pass first."); return; }
            try {
                JSONObject u = new JSONObject().put("id", file.getName().replace(".json", "")).put("takenAt", at / 1000)
                    .put("outcome", outcome[0]).put("note", "");
                if (intensity[0] > 0) u.put("intensity", intensity[0]);
                if (trigger[0] != null) u.put("trigger", trigger[0]);
                if (touched[0]) u.put("caughtEarly", early[0]).put("usedAnchor", anchor[0]);
                if (!place[0]) u.put("noLocation", true);
                writeJSON(file, u);
                saved[0] = true;
                if ("Acted on it".equals(outcome[0])) bumpActed(1);
                if (place[0]) captureLocation(file);
            } catch (Exception e) { toast("Couldn’t save that on this phone."); return; }
            sheet.dismiss();
        }), new LinearLayout.LayoutParams(0, ui.dp(52), 1));
        box.addView(buttons);
        ScrollView scroll = new ScrollView(this); scroll.addView(box);
        sheet.setContentView(scroll);
        sheet.setOnDismissListener(d -> {
            if (!saved[0]) return; // Cancelled: nothing was logged.
            String finalOutcome = outcome[0];
            try {
                JSONArray history = urgeHistory(), next = new JSONArray().put(new JSONObject().put("at", at).put("outcome", finalOutcome));
                for (int i = 0; i < Math.min(history.length(), 19); i++) next.put(history.get(i));
                prefs.edit().putString("urgeHistory", next.toString()).apply();
            } catch (JSONException ignored) {}
            addHistory("Urge · " + (finalOutcome.equals("Acted on it") ? "acted on" : "let it pass"),
                trigger[0] != null ? trigger[0].toLowerCase(Locale.ROOT) : "");
            toast("Urge saved");
            render();
            // Give a pending location a moment to arrive before sending.
            if (locating.contains(file.getName())) main.postDelayed(() -> sync(false, true), 8000); else sync(false, true);
        });
        Window w = sheet.getWindow();
        w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        w.setLayout(Ui.MATCH, Ui.WRAP); w.setGravity(Gravity.BOTTOM);
        w.setDimAmount(0.55f);
        sheet.show();
    }

    // MARK: Spots
    /** Saves where this urge happened (or where the phone is now) as a spot, then makes sure Android may watch it. */
    void saveSpotHere(File urge) {
        if (checkSelfPermission(FINE) != PackageManager.PERMISSION_GRANTED) {
            pendingLocation = urge; requestPermissions(new String[]{FINE, COARSE}, REQ_LOCATION);
            toast("Allow precise location, then tap Save this place again.");
            return;
        }
        double[] here = null;
        try { JSONObject u = SyncEngine.readJSON(urge); if (u.has("latitude")) here = new double[]{u.getDouble("latitude"), u.getDouble("longitude")}; } catch (Exception ignored) {}
        if (here != null) { finishSpot(here[0], here[1]); return; }
        toast("Finding where you are…");
        currentLocation(loc -> { if (loc == null) toast("Couldn’t get your location. Try again outside."); else finishSpot(loc.getLatitude(), loc.getLongitude()); }, "spot");
    }
    void finishSpot(double lat, double lon) {
        try { JSONObject s = SpotReceiver.addSpot(this, lat, lon); toast(s.optString("name") + " saved"); }
        catch (JSONException e) { toast("Couldn’t save the spot."); return; }
        if (checkSelfPermission(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            dialog().setTitle("Check-ins at your spots")
                .setMessage("To ask “Quick check-in?” when you arrive, Android needs location set to “Allow all the time” for Cipher Bridge. Android watches the spot itself, so it costs very little battery.")
                .setPositiveButton("Continue", (d, w) -> askSpotPermissions())
                .setNegativeButton("Not now", null).show();
        }
    }
    View spotsCard() {
        LinearLayout card = ui.card(10);
        card.addView(ui.kicker("Spots"));
        JSONArray spots = SpotReceiver.spots(this);
        boolean watching = SpotReceiver.canWatch(this);
        card.addView(ui.small(spots.length() == 0 ? "Save a spot from the Urge sheet. Arriving there asks a neutral “Quick check-in?”; no answer is kept as a visit."
            : watching ? "Watching " + spots.length() + (spots.length() == 1 ? " spot" : " spots") + " · within " + (int) SpotReceiver.RADIUS_METRES + " m · stays on this phone and your Mac"
            : "Not watching: set location to “Allow all the time” for Cipher Bridge."));
        for (int i = 0; i < spots.length(); i++) {
            JSONObject s = spots.optJSONObject(i);
            LinearLayout row = ui.row(10);
            row.addView(ui.text(s.optString("name"), 15, Ui.TEXT, 500), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            String id = s.optString("id");
            if (s.optBoolean("mac")) row.addView(ui.small("from your Mac"));
            else row.addView(ui.chip("Remove", false, v -> { SpotReceiver.removeSpot(this, id); render(); }), new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(34)));
            card.addView(row);
        }
        if (spots.length() > 0 && !watching) card.addView(ui.secondary("Allow all the time", v -> askSpotPermissions()), Ui.wide());
        return card;
    }
    /** Android only offers "Allow all the time" after precise location is allowed, so ask in that order. */
    void askSpotPermissions() {
        if (checkSelfPermission(FINE) != PackageManager.PERMISSION_GRANTED) requestPermissions(new String[]{FINE, COARSE}, REQ_SPOT_FINE);
        else requestPermissions(new String[]{android.Manifest.permission.ACCESS_BACKGROUND_LOCATION}, REQ_BACKGROUND_LOCATION);
    }

    // MARK: Sets
    /** Condition › Body: latest weigh-in and today's session with the set logger. */
    View body() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        col.addView(weightCard());
        JSONObject w = todayFresh().optJSONObject("workout");
        JSONArray week = todayFresh().optJSONArray("week");
        if (w == null) {
            JSONObject next = null;
            if (week != null) for (int i = 1; i < week.length() && next == null; i++) {
                JSONObject d = week.optJSONObject(i);
                if (d != null && d.optJSONObject("workout") != null) next = d;
            }
            LinearLayout card = ui.card(6);
            card.addView(ui.kicker("Today"));
            card.addView(ui.text("Rest day", 18, Ui.TEXT, 600));
            card.addView(ui.small(week == null ? "Your training plan lives in Cipher on the Mac → Body. Sync to see this week's sessions."
                : next == null ? "Nothing planned in the next 7 days. Add sessions on the Mac → Body." : "No gym today. Recovery is part of the plan."));
            col.addView(card);
            if (next != null) col.addView(planPreview(next));
            if (week != null) col.addView(weekStrip(week));
            col.addView(ui.secondary("Workout artwork · offline", v -> openExerciseDemos()));
            return holder[0];
        }
        String kind = w.optString("kind");
        col.addView(ui.kicker(w.optString("name") + (kind.equals("cardio") && w.has("minutes") ? " · " + fmt(w.optDouble("minutes")) + " min" : "")));
        JSONArray list = w.optJSONArray("exercises");
        if (kind.equals("cardio") || list == null || list.length() == 0) {
            if (kind.equals("cardio") && !w.optString("detail").isEmpty()) {
                LinearLayout card = ui.card(6);
                card.addView(ui.text(w.optString("detail"), 16, Ui.TEXT, 600));
                if (w.has("minutes")) card.addView(ui.mono(fmt(w.optDouble("minutes")) + " min", 13, Ui.ACCENT_TEXT));
                col.addView(card);
            }
            col.addView(ui.small(kind.equals("cardio") ? "Cardio day. Your watch records it; nothing to enter here." : "No exercises in today’s session yet. Add them on the Mac → Body."));
            return holder[0];
        }
        for (int i = 0; i < list.length(); i++) col.addView(exerciseCard(list.optJSONObject(i)));
        if (week != null) col.addView(weekStrip(week));
        return holder[0];
    }
    /** The next planned session, read-only: what to do and what you lifted last time. Sets are entered on the day. */
    View planPreview(JSONObject day) {
        JSONObject w = day.optJSONObject("workout");
        LinearLayout card = ui.card(10);
        LinearLayout head = ui.row(8);
        head.addView(ui.kicker("Next · " + dayName(day)), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (w.has("minutes")) head.addView(ui.mono(fmt(w.optDouble("minutes")) + " min", 12, Ui.ACCENT_TEXT));
        card.addView(head);
        card.addView(serif(w.optString("name"), 24));
        JSONArray list = w.optJSONArray("exercises");
        if ("cardio".equals(w.optString("kind")) || list == null || list.length() == 0) {
            card.addView(ui.small("cardio".equals(w.optString("kind")) ? (w.optString("detail").isEmpty() ? "Cardio. Your watch records it." : w.optString("detail")) : "No exercises in this session yet. Add them on the Mac → Body."));
            return card;
        }
        for (int i = 0; i < list.length(); i++) {
            JSONObject e = list.optJSONObject(i);
            boolean timed = e.optBoolean("timed");
            int minR = e.optInt("minReps"), maxR = e.optInt("maxReps");
            if (i > 0) { View rule = new View(this); rule.setBackgroundColor(Ui.LINE); card.addView(rule, new LinearLayout.LayoutParams(Ui.MATCH, 1)); }
            LinearLayout row = ui.row(10);
            LinearLayout words = ui.column(2);
            words.addView(ui.oneLine(ui.text(e.optString("name"), 15, Ui.TEXT, 600)));
            JSONArray last = e.optJSONArray("last");
            boolean assisted = e.optBoolean("assisted");
            words.addView(ui.oneLine(ui.small(last != null && last.length() > 0 ? "Last: " + setsText(last, timed) + (assisted ? " (assist)" : "")
                : e.has("start") ? "Start at " + fmt(e.optDouble("start")) + " kg" + (assisted ? " assist" : "") : "First time")));
            row.addView(words, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            row.addView(ui.mono(e.optInt("sets") + " × " + (minR == maxR ? String.valueOf(minR) : minR + "–" + maxR) + (timed ? " s" : ""), 12, Ui.MUTED));
            card.addView(row);
        }
        card.addView(ui.small("You enter sets here on the day."));
        return card;
    }
    String setsText(JSONArray sets, boolean timed) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < sets.length(); i++) {
            JSONObject x = sets.optJSONObject(i);
            b.append(i == 0 ? setLabel(x, timed) : ", " + (x.optDouble("weight") == sets.optJSONObject(0).optDouble("weight") ? String.valueOf(x.optInt("reps")) : setLabel(x, timed)));
        }
        return b.toString();
    }
    static String dayName(JSONObject day) {
        try {
            LocalDate d = LocalDate.parse(day.optString("date"));
            if (d.equals(LocalDate.now().plusDays(1))) return "Tomorrow";
            return day.optString("day") + " " + d.getDayOfMonth();
        } catch (Exception e) { return day.optString("day"); }
    }
    /** Seven columns, today first: the session name, or Rest. */
    View weekStrip(JSONArray week) {
        LinearLayout card = ui.card(10);
        card.addView(ui.kicker("This week"));
        LinearLayout row = ui.row(6);
        for (int i = 0; i < week.length(); i++) {
            JSONObject d = week.optJSONObject(i); if (d == null) continue;
            JSONObject w = d.optJSONObject("workout");
            LinearLayout cell = ui.column(4); cell.setGravity(Gravity.CENTER_HORIZONTAL); ui.pad(cell, 2, 10, 2, 10);
            cell.setBackground(i == 0 ? ui.round(Ui.ACCENT_SOFT, 12, Ui.ACCENT, 1) : ui.round(w != null ? Ui.PANEL2 : 0, 12, 0, 0));
            TextView day = ui.mono(i == 0 ? "TODAY" : d.optString("day").toUpperCase(Locale.ROOT), 10, i == 0 ? Ui.LAMP : Ui.MUTED); day.setGravity(Gravity.CENTER);
            cell.addView(day);
            View dot = new View(this); dot.setBackground(ui.round(w == null ? Ui.FAINT : "cardio".equals(w.optString("kind")) ? Ui.GREEN : Ui.ACCENT, 4, 0, 0));
            cell.addView(dot, new LinearLayout.LayoutParams(ui.dp(8), ui.dp(8)));
            TextView name = ui.text(w == null ? "Rest" : w.optString("name"), 11, w == null ? Ui.FAINT : Ui.TEXT, w == null ? 400 : 600);
            name.setGravity(Gravity.CENTER); name.setMaxLines(2); name.setEllipsize(android.text.TextUtils.TruncateAt.END);
            cell.addView(name);
            row.addView(cell, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        }
        card.addView(row);
        return card;
    }
    View weightCard() {
        JSONObject t = todayFresh();
        LinearLayout card = ui.card(4);
        card.addView(ui.kicker("Weight"));
        LinearLayout v = ui.row(4); v.setGravity(Gravity.BOTTOM);
        v.addView(serif(t.has("latestWeight") ? String.format(Locale.US, "%.1f", t.optDouble("latestWeight")) : "—", 30));
        if (t.has("latestWeight")) v.addView(ui.text("kg", 13, Ui.MUTED, 500));
        card.addView(v);
        card.addView(ui.small(t.has("latestWeightAt") ? "Weighed " + ago((long) (t.optDouble("latestWeightAt") * 1000)) : "No weigh-in synced yet"));
        return card;
    }
    static String setLabel(JSONObject s, boolean timed) { return fmt(s.optDouble("weight")) + " × " + s.optInt("reps") + (timed ? " s" : ""); }
    View exerciseCard(JSONObject e) {
        LinearLayout card = ui.card(8);
        boolean timed = e.optBoolean("timed");
        LinearLayout head = ui.row(8);
        head.addView(ui.oneLine(ui.text(e.optString("name"), 15, Ui.TEXT, 600)), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        int minR = e.optInt("minReps"), maxR = e.optInt("maxReps");
        head.addView(ui.mono(e.optInt("sets") + " × " + (minR == maxR ? String.valueOf(minR) : minR + "–" + maxR) + (timed ? " s" : ""), 12, Ui.MUTED));
        card.addView(head);
        JSONArray last = e.optJSONArray("last"), today = e.optJSONArray("today");
        if (last == null) last = new JSONArray();
        if (today == null) today = new JSONArray();
        StringBuilder lastText = new StringBuilder();
        for (int i = 0; i < last.length(); i++) {
            JSONObject s = last.optJSONObject(i);
            lastText.append(i == 0 ? setLabel(s, timed) : ", " + (s.optDouble("weight") == last.optJSONObject(0).optDouble("weight") ? String.valueOf(s.optInt("reps")) : setLabel(s, timed)));
        }
        boolean assisted = e.optBoolean("assisted");
        String first = e.has("start") ? "Start at " + fmt(e.optDouble("start")) + " kg" + (assisted ? " assist" : "") + ", your last known weight."
            : "First time: pick a weight you can do for " + minR + " clean reps.";
        card.addView(ui.small(last.length() == 0 ? first : "Last time: " + lastText + (assisted ? " (kg = assist)" : "")));
        // The planned sets, plus one open cell after the last logged set so an extra set is always possible.
        int total = Math.min(Math.max(e.optInt("sets"), today.length() + 1), 20);
        List<View> cells = new ArrayList<>();
        for (int i = 0; i < total; i++) {
            int index = i;
            JSONObject done = i < today.length() ? today.optJSONObject(i) : null;
            boolean next = i == today.length(), extra = i >= e.optInt("sets");
            LinearLayout cell = ui.column(2); cell.setGravity(Gravity.CENTER); ui.pad(cell, 6, 8, 6, 8);
            cell.setBackground(done != null ? ui.round(Ui.ACCENT_SOFT, 12, 0, 0) : next ? ui.dashed(Ui.PANEL, 12, 0x8CD9B46E) : ui.round(Ui.PANEL2, 12, 0, 0));
            cell.addView(ui.kicker(extra && done == null ? "+ set" : "set " + (i + 1)));
            cell.addView(ui.oneLine(ui.text(done != null ? setLabel(done, timed) : next ? "tap" : "—", 13, done != null ? Ui.TEXT : next ? Ui.ACCENT_TEXT : Ui.FAINT, 600)));
            if (done != null || next) {
                JSONArray lastSets = last, todaySets = today;
                cell.setOnClickListener(Ui.tap(v -> setDialog(e, index, lastSets, todaySets)));
            }
            cell.setMinimumHeight(ui.dp(54));
            cells.add(cell);
        }
        for (int i = 0; i < cells.size(); i += 3) {
            View a = cells.get(i), b = i + 1 < cells.size() ? cells.get(i + 1) : new View(this), c = i + 2 < cells.size() ? cells.get(i + 2) : new View(this);
            card.addView(ui.grid(8, a, b, c));
        }
        return card;
    }
    void setDialog(JSONObject e, int index, JSONArray last, JSONArray today) {
        JSONObject seed = index < today.length() ? today.optJSONObject(index)
            : index > 0 && index - 1 < today.length() ? today.optJSONObject(index - 1)
            : last.length() > 0 ? last.optJSONObject(Math.min(index, last.length() - 1)) : null;
        boolean timed = e.optBoolean("timed");
        EditText kg = new EditText(this), reps = new EditText(this);
        for (EditText f : new EditText[]{kg, reps}) { f.setTextColor(Ui.TEXT); f.setHintTextColor(Ui.FAINT); f.setSelectAllOnFocus(true); }
        kg.setInputType(android.text.InputType.TYPE_CLASS_NUMBER | android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL); kg.setHint("kg");
        reps.setInputType(android.text.InputType.TYPE_CLASS_NUMBER); reps.setHint(timed ? "seconds" : "reps");
        if (seed != null) { kg.setText(fmt(seed.optDouble("weight")).replace(",", "")); reps.setText(String.valueOf(seed.optInt("reps"))); }
        else if (e.has("start")) kg.setText(fmt(e.optDouble("start")).replace(",", ""));
        if (e.optBoolean("assisted")) kg.setHint("kg assist");
        LinearLayout row = ui.row(12); ui.pad(row, 20, 8, 20, 0);
        row.addView(kg, new LinearLayout.LayoutParams(0, Ui.WRAP, 1)); row.addView(ui.text("×", 16, Ui.MUTED, 500)); row.addView(reps, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        dialog().setTitle(e.optString("name") + " · set " + (index + 1)).setView(row)
            .setPositiveButton("Save", (x, w) -> {
                double weight; int r;
                try { weight = Double.parseDouble(kg.getText().toString().trim().replace(",", ".")); r = Integer.parseInt(reps.getText().toString().trim()); }
                catch (NumberFormatException ex) { toast("Enter the weight and reps."); return; }
                if (weight < 0 || weight > 500 || r < 1 || r > 100) { toast("Check the weight and reps."); return; }
                try {
                    engine.recordLog(new JSONObject().put("type", "set").put("exerciseID", e.getString("id")).put("setIndex", index).put("weight", weight).put("reps", r));
                    JSONObject t = engine.today(), wk = t.optJSONObject("workout");
                    JSONArray list = wk == null ? null : wk.optJSONArray("exercises");
                    for (int i = 0; list != null && i < list.length(); i++) {
                        JSONObject x2 = list.getJSONObject(i);
                        if (!x2.optString("id").equals(e.optString("id"))) continue;
                        JSONArray td = x2.optJSONArray("today"); if (td == null) { td = new JSONArray(); x2.put("today", td); }
                        JSONObject s = new JSONObject().put("weight", weight).put("reps", r);
                        if (index < td.length()) td.put(index, s); else td.put(s);
                    }
                    engine.saveToday(t);
                } catch (Exception ex) { toast("Couldn’t save that on this phone."); return; }
                addHistory(e.optString("name") + " · set " + (index + 1), fmt(weight) + "×" + r);
                render(); sync(false, true);
            })
            .setNegativeButton("Cancel", null).show();
    }

    // MARK: Tabs like the Mac
    JSONObject brief() { return todayFresh().optJSONObject("brief"); }
    TextView serif(String s, float sp) { TextView t = ui.text(s, sp, Ui.TEXT, 600); t.setTypeface(Ui.serif(600)); t.setLetterSpacing(-0.01f); return t; }
    View noBrief() {
        LinearLayout card = ui.card(6);
        card.addView(ui.text("Sync to fill this in", 16, Ui.TEXT, 600));
        card.addView(ui.small("This page comes from Cipher on your Mac. Tap the sync pill on Brief › Today when you're on the same Wi-Fi."));
        return card;
    }
    /** The Mac's page head: kicker, serif title and countdown, then the open tab's sub-tabs as pills. */
    View tabHead() {
        JSONObject b = brief();
        LinearLayout col = ui.column(14);
        String title;
        switch (screen) {
            case GOALS: title = "The blueprint."; break;
            case ROUTINE: title = "Find your rhythm."; break;
            case HEALTH: title = "Know your rhythm."; break;
            case BODY: title = "Build strength. See change."; break;
            case SCREEN_TIME: title = "Own your attention."; break;
            case MEALS: title = "Eat with intent."; break;
            case MEDS: title = "Take it as prescribed."; break;
            case URGES: title = "Notice the pattern."; break;
            case NOTES: title = "Remember what matters."; break;
            case DOSSIER: title = "The Dossier."; break;
            default: title = "The Brief.";
        }
        String kicker = "Your next version starts here";
        if (screen == Screen.HEALTH) kicker = "Condition report · " + LocalDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM · h:mm a", Locale.ENGLISH));
        else if (screen == Screen.SCREEN_TIME) kicker = "Your attention";
        else if (screen == Screen.BODY) {
            JSONObject a = b == null || b.optJSONArray("missions") == null ? null : b.optJSONArray("missions").optJSONObject(0);
            kicker = a == null ? "Mission A" : "Mission A · " + a.optString("codename");
        }
        LinearLayout row = ui.row(10); row.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout text = ui.column(4);
        text.addView(ui.oneLine(ui.kicker(kicker)));
        TextView t = serif(title, title.length() > 22 ? 25 : 30); t.setMaxLines(2);
        text.addView(t);
        row.addView(text, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        if (b != null && b.has("daysLeft")) {
            LinearLayout d = ui.column(0); d.setGravity(Gravity.END);
            TextView n = serif(String.valueOf(b.optInt("daysLeft")), 26); n.setGravity(Gravity.END); d.addView(n);
            TextView l = ui.kicker("days"); l.setGravity(Gravity.END); d.addView(l);
            row.addView(d);
        }
        row.addView(circleButton("ic_eye_off", "Eyes only", v -> sealEyes()));
        row.addView(circleButton("ic_gear", "Settings", v -> show(Screen.SETTINGS)));
        col.addView(row);
        Screen[] subs = GROUPS[Math.max(0, group(screen))];
        if (subs.length > 1) {
            HorizontalScrollView scroll = new HorizontalScrollView(this);
            scroll.setHorizontalScrollBarEnabled(false); scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
            LinearLayout pills = ui.row(6);
            for (Screen s : subs) {
                boolean on = s == screen;
                TextView p = ui.text(subLabel(s), 13, on ? Ui.LAMP : Ui.MUTED, on ? 600 : 500);
                p.setGravity(Gravity.CENTER);
                p.setBackground(ui.round(on ? 0x24D9B46E : 0, 18, on ? 0x80D9B46E : 0x24F1E8D4, 1));
                ui.pad(p, 16, 0, 16, 0);
                p.setContentDescription(subLabel(s));
                p.setOnClickListener(Ui.tap(v -> show(s)));
                pills.addView(p, new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(36)));
            }
            scroll.addView(pills);
            col.addView(scroll);
        }
        return col;
    }

    // MARK: Brief › Goals
    View goals() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        JSONObject b = brief();
        if (b == null) { col.addView(noBrief()); return holder[0]; }
        JSONObject c = b.optJSONObject("clearance");
        JSONArray ms = b.optJSONArray("missions");
        if (c != null) {
            TextView k = ui.kicker("Clearance " + c.optJSONArray("marks").optString(c.optInt("level") - 1) + " · " + c.optJSONArray("ranks").optString(c.optInt("level") - 1));
            k.setTextColor(Ui.ACCENT); col.addView(k);
        }
        if (ms != null && ms.length() > 0) {
            double[] values = new double[ms.length()]; String[] labels = new String[ms.length()];
            for (int i = 0; i < ms.length(); i++) { values[i] = ms.optJSONObject(i).optDouble("progress", 0); labels[i] = ms.optJSONObject(i).optString("id"); }
            LinearLayout radarCard = ui.card(6);
            radarCard.addView(new RadarView(this, values, labels, ui), new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(250)));
            TextView cap = ui.kicker("The shape grows to the gold line as you hit targets"); cap.setTextColor(Ui.GOLD_DIM); cap.setTextSize(8.5f); cap.setGravity(Gravity.CENTER);
            radarCard.addView(cap);
            col.addView(radarCard);
        }
        LinearLayout orders = ui.card(10);
        orders.addView(ui.kicker("Orders / the three most behind"));
        JSONArray os = b.optJSONArray("orders");
        if (os == null || os.length() == 0) orders.addView(serif("All targets on plan. Hold the line.", 20));
        for (int i = 0; os != null && i < os.length(); i++) {
            JSONObject o = os.optJSONObject(i);
            if (i > 0) orders.addView(ui.divider());
            LinearLayout r = ui.row(12); r.setGravity(Gravity.TOP);
            TextView num = serif(String.format(Locale.ROOT, "%02d", i + 1), 22); num.setTextColor(Ui.ACCENT); r.addView(num);
            LinearLayout tx = ui.column(3);
            tx.addView(ui.text(o.optString("title"), 15, Ui.TEXT, 600));
            tx.addView(ui.mono(o.optString("line"), 11, o.optBoolean("logged") ? Ui.ORANGE : Ui.MUTED));
            r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            TextView m = serif(o.optString("mission"), 18); m.setTextColor(Ui.GOLD_DIM); r.addView(m);
            orders.addView(r);
        }
        orders.addView(ui.divider());
        orders.addView(ui.grid(8,
            bigStat(b.optInt("measured") + " of " + b.optInt("targets"), "targets measured"),
            bigStat(String.valueOf(b.optInt("behind")), "behind plan"),
            bigStat(String.valueOf(b.optInt("milestones")), "milestones done")));
        col.addView(orders);
        LinearLayout list = ui.card(0);
        for (int i = 0; ms != null && i < ms.length(); i++) {
            JSONObject m = ms.optJSONObject(i);
            if (i > 0) list.addView(ui.divider());
            LinearLayout block = ui.column(8); ui.pad(block, 0, 12, 0, 12);
            LinearLayout top = ui.row(12); top.setGravity(Gravity.CENTER_VERTICAL);
            TextView letter = serif(m.optString("id"), 26); letter.setTextColor(Ui.ACCENT_TEXT); top.addView(letter, ui.size(26, -2));
            LinearLayout names = ui.column(2);
            names.addView(ui.oneLine(ui.kicker(m.optString("codename"))));
            names.addView(ui.oneLine(serif(m.optString("title"), 19)));
            top.addView(names, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            top.addView(serif(Math.round(m.optDouble("progress") * 100) + "%", 18));
            block.addView(top);
            block.addView(ui.bar(Math.max(0.01, m.optDouble("progress")), Ui.ACCENT));
            LinearLayout foot = ui.row(8); foot.setGravity(Gravity.CENTER_VERTICAL);
            String st = m.optString("status");
            TextView chip = ui.mono(st.toUpperCase(Locale.ROOT), 9.5f, st.equals("On plan") ? Ui.GREEN : Ui.ORANGE);
            chip.setBackground(ui.round(0, 10, st.equals("On plan") ? 0x8086D19F : 0x80E6B04E, 1)); ui.pad(chip, 8, 2, 8, 2);
            foot.addView(chip);
            View gap = new View(this); foot.addView(gap, new LinearLayout.LayoutParams(0, 1, 1));
            foot.addView(ui.mono(m.optString("due").toUpperCase(Locale.ROOT), 10, Ui.MUTED));
            block.addView(foot);
            list.addView(block);
        }
        col.addView(list);
        col.addView(ui.small("Missions and targets are edited on the Mac → Brief → Goals."));
        return holder[0];
    }
    View bigStat(String value, String label) {
        LinearLayout c = ui.column(2);
        c.addView(serif(value, 20));
        TextView l = ui.kicker(label); l.setTextSize(8.5f); c.addView(l);
        return c;
    }
    /** The Mac's mission pentagon: grid rings, the gold target line, and the filled shape of progress. */
    static final class RadarView extends View {
        final double[] values; final String[] labels; final Ui ui;
        final android.graphics.Paint line = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        RadarView(android.content.Context c, double[] values, String[] labels, Ui ui) { super(c); this.values = values; this.labels = labels; this.ui = ui; }
        float[] point(int i, float r, float cx, float cy) {
            double a = -Math.PI / 2 + i * 2 * Math.PI / values.length;
            return new float[]{cx + (float) (Math.cos(a) * r), cy + (float) (Math.sin(a) * r)};
        }
        android.graphics.Path shape(float r, float cx, float cy, double[] scale) {
            android.graphics.Path p = new android.graphics.Path();
            for (int i = 0; i < values.length; i++) {
                float[] pt = point(i, (float) (r * (scale == null ? 1 : Math.max(0.04, Math.min(1, scale[i])))), cx, cy);
                if (i == 0) p.moveTo(pt[0], pt[1]); else p.lineTo(pt[0], pt[1]);
            }
            p.close(); return p;
        }
        @Override protected void onDraw(android.graphics.Canvas canvas) {
            float cx = getWidth() / 2f, cy = getHeight() / 2f + ui.dp(6), r = Math.min(getWidth(), getHeight()) / 2f - ui.dp(30);
            line.setStyle(android.graphics.Paint.Style.STROKE); line.setStrokeWidth(ui.dp(1));
            line.setColor(0x1FF1E8D4);
            for (int k = 1; k <= 3; k++) canvas.drawPath(shape(r * k / 4f, cx, cy, null), line);
            for (int i = 0; i < values.length; i++) { float[] pt = point(i, r, cx, cy); canvas.drawLine(cx, cy, pt[0], pt[1], line); }
            line.setColor(Ui.ACCENT); line.setStrokeWidth(ui.dp(1.5f));
            canvas.drawPath(shape(r, cx, cy, null), line);
            android.graphics.Path fill = shape(r, cx, cy, values);
            line.setStyle(android.graphics.Paint.Style.FILL); line.setColor(0x4DF0D49A); canvas.drawPath(fill, line);
            line.setStyle(android.graphics.Paint.Style.STROKE); line.setColor(Ui.LAMP); canvas.drawPath(fill, line);
            android.graphics.Paint label = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
            label.setTextAlign(android.graphics.Paint.Align.CENTER);
            for (int i = 0; i < values.length; i++) {
                float[] pt = point(i, r + ui.dp(17), cx, cy);
                label.setTypeface(Ui.serif(600)); label.setTextSize(ui.dp(18)); label.setColor(Ui.ACCENT_TEXT);
                canvas.drawText(labels[i], pt[0], pt[1], label);
                label.setTypeface(Ui.monoFace(500)); label.setTextSize(ui.dp(9)); label.setColor(Ui.MUTED);
                canvas.drawText(Math.round(values[i] * 100) + "%", pt[0], pt[1] + ui.dp(12), label);
            }
        }
    }

    // MARK: Brief › Routine
    View routine() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        JSONObject b = brief();
        if (b == null) { col.addView(noBrief()); return holder[0]; }
        col.addView(serif(b.optString("routineLine"), 23));
        LinearLayout card = ui.card(0);
        LinearLayout head = ui.row(8);
        TextView k = ui.kicker("The night ahead"); k.setTextColor(Ui.ACCENT);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        head.addView(ui.small("From your plan · nothing to tap"));
        card.addView(head);
        LinearLayout nowRow = ui.row(10); nowRow.setGravity(Gravity.CENTER_VERTICAL); ui.pad(nowRow, 0, 12, 0, 6);
        nowRow.addView(timeCell(LocalTime.now().format(java.time.format.DateTimeFormatter.ofPattern("h:mm a", Locale.ENGLISH)).toLowerCase(Locale.ROOT), Ui.ACCENT));
        View dot = new View(this); dot.setBackground(ui.round(Ui.ACCENT, 5, 0x40D9B46E, 4)); nowRow.addView(dot, ui.size(12, 12));
        TextView nk = ui.kicker("Now"); nk.setTextColor(Ui.ACCENT); nowRow.addView(nk);
        card.addView(nowRow);
        JSONArray items = b.optJSONArray("routine");
        if (items == null || items.length() == 0) card.addView(ui.small("Nothing left on the plan tonight."));
        for (int i = 0; items != null && i < items.length(); i++) {
            JSONObject e = items.optJSONObject(i);
            if (i > 0) card.addView(ui.divider());
            boolean current = e.optBoolean("current"), done = e.optBoolean("done");
            String kind = e.optString("kind");
            LinearLayout r = ui.row(10); r.setGravity(Gravity.CENTER_VERTICAL); ui.pad(r, current ? 6 : 0, 9, current ? 6 : 0, 9);
            if (current) r.setBackground(ui.round(0x14D9B46E, 10, 0, 0));
            r.addView(timeCell(e.optString("time"), Ui.MUTED));
            View m = new View(this);
            boolean solid = kind.equals("windDown") || kind.equals("bed");
            m.setBackground(solid ? ui.round(kind.equals("bed") ? Ui.TEXT : Ui.LAMP, 5, 0, 0) : ui.round(0, 5, done ? Ui.GREEN : kind.equals("meds") ? Ui.ACCENT : Ui.GOLD_DIM, 1.5f));
            r.addView(m, ui.size(10, 10));
            LinearLayout tx = ui.column(2);
            TextView title = kind.equals("windDown") ? serif(e.optString("title"), 20) : ui.text(e.optString("title"), 14.5f, done ? Ui.GREEN : Ui.TEXT, 500);
            tx.addView(title);
            if (!e.optString("detail").isEmpty()) tx.addView(ui.oneLine(ui.small(e.optString("detail"))));
            r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
            r.addView(ui.mono(e.optString("status"), 10.5f, done ? Ui.GREEN : current ? Ui.ACCENT : Ui.MUTED));
            card.addView(r);
        }
        JSONArray earlier = b.optJSONArray("earlier");
        if (earlier != null && earlier.length() > 0) {
            card.addView(ui.divider());
            LinearLayout e = ui.column(6); ui.pad(e, 0, 12, 0, 0);
            e.addView(ui.kicker("Earlier today"));
            for (int i = 0; i < earlier.length(); i++) {
                String s = earlier.optString(i);
                boolean warn = s.endsWith("not tapped");
                TextView chip = ui.text(s, 12, warn ? Ui.ORANGE : Ui.MUTED, 500);
                chip.setBackground(ui.round(0, 14, warn ? 0x59E6B04E : 0x24F1E8D4, 1)); ui.pad(chip, 10, 4, 10, 4);
                e.addView(chip, new LinearLayout.LayoutParams(Ui.WRAP, Ui.WRAP));
            }
            card.addView(e);
        }
        col.addView(card);
        col.addView(ui.small("Times come from your routine on the Mac → Brief → Routine → Edit times."));
        return holder[0];
    }
    TextView timeCell(String s, int color) { TextView t = ui.mono(s, 11, color); t.setGravity(Gravity.END); t.setLayoutParams(ui.size(66, -2)); return t; }

    // MARK: Condition › Health
    View health() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        JSONObject t = todayFresh();
        if (t.length() == 0) { col.addView(noBrief()); return holder[0]; }
        col.addView(lastNight(t));
        col.addView(daySoFar(t));
        LinearLayout meds = ui.card(4);
        meds.addView(ui.kicker("Meds this week"));
        meds.addView(ui.text(t.optInt("medsWeekTaken") + " taken · " + t.optInt("medsWeekMissed") + " missed", 16, t.optInt("medsWeekMissed") > 0 ? Ui.ORANGE : Ui.TEXT, 600));
        col.addView(meds);
        col.addView(ui.small("Heart rate, stress and the full charts are on the Mac → Condition → Health."));
        return holder[0];
    }

    // MARK: Condition › Screen time
    View screenTime() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        JSONObject b = brief();
        JSONArray days = b == null ? null : b.optJSONArray("screenDays");
        if (days == null || days.length() == 0) {
            LinearLayout card = ui.card(6);
            card.addView(ui.text("No phone screen time yet", 16, Ui.TEXT, 600));
            card.addView(ui.small("Turn on Settings → Share screen time with Mac and allow Usage access, then sync."));
            card.addView(ui.secondary("Open Settings", v -> show(Screen.SETTINGS)), Ui.wide());
            col.addView(card);
            return holder[0];
        }
        col.addView(serif(b.optString("screenLine"), 23));
        LinearLayout card = ui.card(10);
        LinearLayout head = ui.row(8);
        TextView k = ui.kicker("Phone · last 7 days"); k.setTextColor(Ui.ACCENT);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        card.addView(head);
        double most = 1;
        for (int i = 0; i < days.length(); i++) most = Math.max(most, days.optJSONObject(i).optDouble("minutes", 0));
        LinearLayout bars = ui.row(6); bars.setGravity(Gravity.BOTTOM);
        for (int i = 0; i < days.length(); i++) {
            JSONObject d = days.optJSONObject(i);
            double min = d.optDouble("minutes", Double.NaN);
            LinearLayout c = ui.column(4); c.setGravity(Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM);
            TextView v = ui.mono(Double.isNaN(min) ? "—" : hm(min), 8.5f, Ui.SOFT); v.setGravity(Gravity.CENTER); c.addView(v);
            View bar = new View(this);
            bar.setBackground(ui.round(d.optBoolean("shown") ? Ui.LAMP : 0xFF7F7D55, 3, 0, 0));
            c.addView(bar, new LinearLayout.LayoutParams(Ui.MATCH, ui.dp(Double.isNaN(min) ? 2 : Math.max(3, (float) (130 * min / most)))));
            TextView l = ui.mono(d.optString("label").toUpperCase(Locale.ROOT), 8.5f, Ui.MUTED); l.setGravity(Gravity.CENTER); c.addView(l);
            bars.addView(c, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        }
        card.addView(bars);
        col.addView(card);
        JSONArray apps = b.optJSONArray("topApps");
        if (apps != null && apps.length() > 0) {
            LinearLayout ac = ui.card(10);
            TextView ak = ui.kicker("Top apps"); ak.setTextColor(Ui.ACCENT); ac.addView(ak);
            double top = Math.max(1, apps.optJSONObject(0).optDouble("minutes"));
            for (int i = 0; i < apps.length(); i++) {
                JSONObject a = apps.optJSONObject(i);
                LinearLayout r = ui.row(10); r.setGravity(Gravity.CENTER_VERTICAL);
                LinearLayout n = ui.column(6);
                n.addView(ui.oneLine(ui.text(a.optString("name"), 13, Ui.TEXT, 500)));
                n.addView(ui.bar(a.optDouble("minutes") / top, Ui.ACCENT));
                r.addView(n, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                r.addView(ui.mono(hm(a.optDouble("minutes")), 11, Ui.MUTED));
                ac.addView(r);
            }
            col.addView(ac);
        }
        col.addView(ui.small("Late-night use and this Mac's own screen time are on the Mac → Condition → Screen time."));
        return holder[0];
    }
    static String hm(double minutes) { long m = Math.round(minutes); return m >= 60 ? (m / 60) + "h " + String.format(Locale.ROOT, "%02d", m % 60) : m + "m"; }

    // MARK: Field log › Notes
    View notes() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        JSONObject b = brief();
        if (b == null) { col.addView(noBrief()); return holder[0]; }
        TextView k = ui.kicker("Plans, decisions and reflections worth keeping"); col.addView(k);
        JSONArray notes = b.optJSONArray("notes");
        if (notes == null || notes.length() == 0) col.addView(ui.small("No notes yet. Write them on the Mac → Field log → Notes, or save a chat with Q."));
        for (int i = 0; notes != null && i < notes.length(); i++) {
            JSONObject n = notes.optJSONObject(i);
            LinearLayout card = ui.card(6);
            LinearLayout head = ui.row(8); head.setGravity(Gravity.CENTER_VERTICAL);
            head.addView(ui.text(n.optString("kind") + (n.optBoolean("pinned") ? " · pinned" : ""), 11, Ui.ACCENT, 500));
            View gap = new View(this); head.addView(gap, new LinearLayout.LayoutParams(0, 1, 1));
            head.addView(ui.mono(n.optString("date"), 10.5f, Ui.MUTED));
            card.addView(head);
            card.addView(ui.text(n.optString("title"), 15, Ui.TEXT, 600));
            String body = n.optString("body").replace("**", "");
            if (!body.isEmpty()) {
                TextView bt = ui.text(body, 12.5f, Ui.SOFT, 400); bt.setMaxLines(5); bt.setEllipsize(android.text.TextUtils.TruncateAt.END);
                card.addView(bt);
                bt.setOnClickListener(v -> { boolean open = bt.getMaxLines() > 5; bt.setMaxLines(open ? 5 : 200); });
            }
            col.addView(card);
        }
        col.addView(ui.small("Read-only here. New notes are written on the Mac."));
        return holder[0];
    }

    // MARK: Dossier
    View dossier() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, true);
        col.addView(tabHead());
        JSONObject b = brief();
        if (b == null) { col.addView(noBrief()); return holder[0]; }
        JSONObject c = b.optJSONObject("clearance");
        if (c != null) {
            int level = c.optInt("level", 1);
            JSONArray marks = c.optJSONArray("marks"), ranks = c.optJSONArray("ranks"), rewards = c.optJSONArray("rewards");
            LinearLayout card = ui.card(10);
            card.setBackground(ui.round(0xFF0F3026, 18, 0x33D9B46E, 1));
            TextView k = ui.kicker("Clearance · " + ranks.optString(level - 1)); k.setTextColor(Ui.ACCENT); card.addView(k);
            card.addView(serif(level == 5 ? "Double-O. Licensed." : "You hold Clearance " + marks.optString(level - 1) + ".", 28));
            card.addView(ui.small(c.optString("next")));
            card.addView(ui.kicker("This week so far"));
            card.addView(ui.mono(c.optString("week"), 11.5f, Ui.TEXT));
            HorizontalScrollView hs = new HorizontalScrollView(this); hs.setHorizontalScrollBarEnabled(false);
            LinearLayout plates = ui.row(8);
            for (int i = 0; i < marks.length(); i++) {
                boolean earned = i + 1 <= level, current = i + 1 == level;
                LinearLayout p = ui.column(6); ui.pad(p, 12, 12, 12, 12);
                p.setBackground(ui.round(current ? Ui.PANEL2 : 0x590B2A21, 10, current ? 0xCCF0D49A : Ui.LINE, current ? 1.5f : 1));
                LinearLayout top = ui.row(6); top.setGravity(Gravity.CENTER_VERTICAL);
                TextView mk = serif(marks.optString(i), 28); mk.setTextColor(earned ? Ui.LAMP : Ui.GOLD_DIM);
                top.addView(mk, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                top.addView(ui.iconView(earned ? "ic_check" : "ic_close", earned ? Ui.ACCENT : Ui.FAINT, 14));
                p.addView(top);
                TextView rk = ui.kicker(ranks.optString(i)); rk.setTextSize(8.5f); if (current) rk.setTextColor(Ui.ACCENT); p.addView(rk);
                TextView rw = ui.text(rewards.optString(i), 11, earned ? Ui.TEXT : Ui.MUTED, 400); rw.setMaxLines(3); p.addView(rw);
                plates.addView(p, new LinearLayout.LayoutParams(ui.dp(150), ui.dp(128)));
            }
            hs.addView(plates);
            card.addView(hs);
            TextView rules = ui.mono("Clean week: 3 gym sessions, 70% of check-ins, 4 nights asleep by 1 am. Slack week (no gym, or under 40% of check-ins) drops one level.", 9.5f, Ui.GOLD_DIM);
            card.addView(rules);
            col.addView(card);
        }
        JSONObject memo = b.optJSONObject("memo");
        if (memo != null) col.addView(memoCard(memo));
        JSONArray sections = b.optJSONArray("sections");
        for (int i = 0; sections != null && i < sections.length(); i++) {
            JSONObject s = sections.optJSONObject(i);
            LinearLayout card = ui.card(8);
            card.addView(serif(s.optString("title"), 22));
            card.addView(ui.small(s.optString("blurb")));
            JSONArray items = s.optJSONArray("items");
            if (items == null || items.length() == 0) card.addView(ui.small("Nothing here yet."));
            for (int j = 0; items != null && j < items.length(); j++) {
                JSONObject it = items.optJSONObject(j);
                card.addView(ui.divider());
                LinearLayout r = ui.row(8); r.setGravity(Gravity.CENTER_VERTICAL);
                LinearLayout tx = ui.column(2);
                LinearLayout name = ui.row(6); name.setGravity(Gravity.CENTER_VERTICAL);
                name.addView(ui.text(it.optString("title"), 14, Ui.TEXT, 600));
                if (it.optBoolean("placeholder")) { TextView ph = ui.kicker("placeholder"); ph.setTextSize(8); ph.setTextColor(Ui.GOLD_DIM); name.addView(ph); }
                tx.addView(name);
                if (!it.optString("detail").isEmpty()) tx.addView(ui.small(it.optString("detail")));
                if (it.has("progress")) { tx.addView(ui.bar(Math.max(0.01, it.optDouble("progress")), Ui.ACCENT)); }
                r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                TextView tag = ui.mono(it.optString("tag").toUpperCase(Locale.ROOT), 9, it.optString("tag").equals("Owned") ? Ui.GREEN : Ui.ACCENT_TEXT);
                tag.setBackground(ui.round(0, 10, it.optString("tag").equals("Owned") ? 0x8086D19F : 0x59D9B46E, 1)); ui.pad(tag, 8, 2, 8, 2);
                r.addView(tag);
                card.addView(r);
            }
            col.addView(card);
        }
        col.addView(ui.small("Placeholders are marked. Edit any line on the Mac → Dossier; it stays on your devices."));
        return holder[0];
    }
    /** M's daily memo, on paper like the Mac's Today: yesterday, the goals, and up to three orders. Tap to fold. */
    View dailyMemoCard(JSONObject memo, String date) {
        int paper = 0xFFF1E8D4, ink = 0xFF1D2A24, soft = 0xB31D2A24, red = 0xFF9E2B33, green = 0xFF2F6B4A;
        LinearLayout card = ui.column(10); ui.pad(card, 18, 18, 18, 18);
        card.setBackground(ui.round(paper, 12, 0, 0));
        LinearLayout head = ui.row(8);
        TextView k = ui.kicker("Memorandum · from M · daily"); k.setTextColor(soft);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        head.addView(ui.mono(date, 10, soft));
        card.addView(head);
        View rule = new View(this); rule.setBackgroundColor(0x401D2A24); card.addView(rule, new LinearLayout.LayoutParams(Ui.MATCH, 1));
        TextView open = ui.text("007. " + memo.optString("opening"), 18, ink, 500); open.setTypeface(Ui.serif(500), android.graphics.Typeface.ITALIC);
        card.addView(open);
        LinearLayout body = ui.column(10);
        for (String[] part : new String[][]{{"yesterday", "Yesterday"}, {"goals", "Goals"}}) {
            JSONArray lines = memo.optJSONArray(part[0]);
            if (lines == null || lines.length() == 0) continue;
            TextView pk = ui.kicker(part[1]); pk.setTextColor(soft); body.addView(pk);
            for (int i = 0; i < lines.length(); i++) {
                JSONObject l = lines.optJSONObject(i);
                LinearLayout r = ui.row(8); r.setGravity(Gravity.TOP);
                View dot = new View(this);
                int color = !l.has("good") || l.isNull("good") ? 0x4D1D2A24 : l.optBoolean("good") ? green : red;
                dot.setBackground(ui.round(color, 4, 0, 0));
                LinearLayout.LayoutParams dp = new LinearLayout.LayoutParams(ui.dp(7), ui.dp(7)); dp.topMargin = ui.dp(6); r.addView(dot, dp);
                TextView t = ui.text(l.optString("label") + "  " + l.optString("text"), 13, ink, 400);
                r.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                body.addView(r);
            }
        }
        JSONArray orders = memo.optJSONArray("orders");
        if (orders != null && orders.length() > 0) {
            TextView tk = ui.kicker("Today"); tk.setTextColor(red); body.addView(tk);
            for (int i = 0; i < orders.length(); i++) {
                LinearLayout r = ui.row(10); r.setGravity(Gravity.TOP);
                r.addView(ui.mono((i + 1) + ".", 13, red));
                TextView o = ui.text(orders.optString(i), 16, ink, 600); o.setTypeface(Ui.serif(600));
                r.addView(o, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
                body.addView(r);
            }
        }
        card.addView(body);
        LinearLayout foot = ui.row(8); foot.setGravity(Gravity.CENTER_VERTICAL);
        foot.addView(ui.mono("Urges stay in Field log", 9, soft), new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        TextView m = ui.text("— M", 16, ink, 500); m.setTypeface(Ui.serif(500), android.graphics.Typeface.ITALIC); foot.addView(m);
        card.addView(foot);
        card.setOnClickListener(Ui.tap(x -> body.setVisibility(body.getVisibility() == View.GONE ? View.VISIBLE : View.GONE)));
        return card;
    }
    /** M's weekly memorandum, on paper like the Mac. */
    View memoCard(JSONObject memo) {
        int paper = 0xFFF1E8D4, ink = 0xFF1D2A24, red = 0xFF9E2B33;
        LinearLayout card = ui.column(10); ui.pad(card, 18, 18, 18, 18);
        card.setBackground(ui.round(paper, 12, 0, 0));
        LinearLayout head = ui.row(8);
        TextView k = ui.kicker("Memorandum · from M"); k.setTextColor(0xB31D2A24);
        head.addView(k, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        head.addView(ui.mono(memo.optString("week"), 10, 0xB31D2A24));
        card.addView(head);
        View rule = new View(this); rule.setBackgroundColor(0x401D2A24); card.addView(rule, new LinearLayout.LayoutParams(Ui.MATCH, 1));
        for (String part : new String[]{"wins", "misses"}) {
            TextView pk = ui.kicker(part); pk.setTextColor(0xB31D2A24); card.addView(pk);
            JSONArray list = memo.optJSONArray(part);
            for (int i = 0; list != null && i < list.length(); i++) card.addView(ui.text("· " + list.optString(i), 13, ink, 400));
        }
        TextView ok = ui.kicker("Order"); ok.setTextColor(red); ok.setTypeface(Ui.monoFace(700)); card.addView(ok);
        TextView order = serif(memo.optString("order"), 20); order.setTextColor(ink); card.addView(order);
        TextView sign = serif("— M", 18); sign.setTextColor(0xCC1D2A24); sign.setGravity(Gravity.END); card.addView(sign);
        return card;
    }

    // MARK: Settings
    View settings() {
        ViewGroup[] holder = new ViewGroup[1];
        LinearLayout col = page(holder, false);
        col.addView(topBar("Settings", lastInTab[0], null));
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
            mac.addView(ui.body("Not paired. On the Mac, open Cipher → Health → Pair phone, then tap Pair with Mac."));
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
        LinearLayout usage = ui.card(12);
        usage.addView(ui.kicker("Screen time"));
        usage.addView(toggle("Share screen time with Mac", "Daily screen-on time and per-app foreground time. No screen images, messages or browsing content.",
            ScreenTimeCollector.sharing(this), on -> {
                prefs.edit().putBoolean("screenTimeSharing",on).apply();
                if (!on) prefs.edit().putBoolean("screenTimeBackground",false).apply();
                if (on && !ScreenTimeCollector.allowed(this)) openUsageAccess();
                SyncJob.schedule(this,false);render();
            }));
        usage.addView(ui.small(ScreenTimeCollector.allowed(this) ? "Usage access allowed · detailed Android history may cover only a few days" : "Usage access is not allowed. Enable it in Android Settings to share readings."));
        usage.addView(ui.secondary("Manage Usage access",v -> openUsageAccess()),Ui.wide());
        usage.addView(toggle("Screen time in background", "About hourly on Wi-Fi when your paired Mac is reachable. Independent of Health Connect.",
            prefs.getBoolean("screenTimeBackground",false),on -> {
                if (on && (!ScreenTimeCollector.sharing(this) || !ScreenTimeCollector.allowed(this))) { toast("Turn on sharing and allow Usage access first.");render();return; }
                prefs.edit().putBoolean("screenTimeBackground",on).apply();
                toast(SyncJob.schedule(this,on) ? "Screen-time background preference saved" : "Android could not schedule background sync");render();
            }));
        col.addView(usage);
        col.addView(spotsCard());
        LinearLayout sync = ui.card(14);
        sync.addView(ui.kicker("Syncing"));
        sync.addView(toggle("Sync in the background", engine.backgroundAllowed() ? "Every hour on Wi-Fi when your Mac is reachable" : "Needs “Access data in the background” in Health Connect",
            prefs.getBoolean("backgroundSync", false) && engine.backgroundAllowed(), on -> {
                if (on && !engine.backgroundAllowed()) { requestPermissions(new String[]{SyncEngine.BACKGROUND}, REQ_BACKGROUND); return; }
                prefs.edit().putBoolean("backgroundSync", on).apply();
                boolean scheduled = SyncJob.schedule(this, on);
                toast(!on ? "Background sync off" : scheduled ? "Background sync on" : "Android didn’t allow the background job. Try again later."); render();
            }));
        sync.addView(toggle("Lock when I leave the app", "Eyes only: opens on the vault every time; fingerprint or PIN to get in", lockOnLeave(), on -> {
            prefs.edit().putBoolean("eyesLockOnLeave", on).apply(); setRecentsScreenshotEnabled(!on);
        }));
        sync.addView(toggle("Sync when I open the app", "Quietly sends anything waiting", prefs.getBoolean("autoSync", true), on -> prefs.edit().putBoolean("autoSync", on).apply()));
        sync.addView(toggle("Medicine reminders", remindersOn() ? "At each prescribed time, with a Taken button" : "Notifications are off for Cipher Bridge", remindersOn(), on -> enableReminders()));
        col.addView(sync);
        LinearLayout privacy = ui.column(8); ui.pad(privacy, 4, 4, 4, 0);
        privacy.addView(ui.kicker("Privacy"));
        privacy.addView(ui.small("Reads the Mi Fitness records you allow and never writes health data. Optional screen-time sharing reads usage summaries only after you enable Usage access. Photos are resized and stripped of location. Everything goes straight to your Mac over Wi-Fi, encrypted with the key from pairing. No account, cloud or developer options."));
        col.addView(privacy);
        TextView version = ui.small("Cipher Bridge " + VERSION); version.setGravity(Gravity.CENTER); version.setTextSize(11);
        col.addView(version);
        return holder[0];
    }
    void openUsageAccess() {
        try { startActivity(new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS,Uri.parse("package:"+getPackageName()))); }
        catch (android.content.ActivityNotFoundException e) { startActivity(new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)); }
    }
    View toggle(String title, String subtitle, boolean on, Consumer<Boolean> changed) {
        LinearLayout row = ui.row(12);
        LinearLayout t = ui.column(2);
        t.addView(ui.text(title, 15, Ui.TEXT, 500));
        t.addView(ui.small(subtitle));
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1));
        Switch s = new Switch(this);
        s.setChecked(on);
        s.setThumbTintList(Ui.tint(Ui.TEXT, Ui.MUTED)); s.setTrackTintList(Ui.tint(Ui.ACCENT, 0xFF2F5C4C));
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
            if (target == null) { finishSync(quiet ? null : "Couldn’t find " + engine.macName() + " on this Wi-Fi. Open Cipher on the Mac and try again."); return; }
            if (health && engine.allowedCount() > 0 && readableForeground()) {
                getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                engine.readHealth(this::readableForeground, (snapshot, problem) ->
                    network.execute(() -> finishSync(engine.sendAll(target, snapshot, problem == null ? "" : problem + "\n"))));
            } else network.execute(() -> finishSync(engine.sendAll(target, null, "")));
        })), () -> finishSync("Cipher Bridge needs local network access to reach your Mac. Allow it in Settings → Apps → Cipher Bridge."));
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
            else toast("Cipher Bridge needs local network access to reach your Mac. Allow it in Settings → Apps → Cipher Bridge.");
        } else if (code == REQ_BACKGROUND) {
            prefs.edit().putBoolean("backgroundSync", ok).apply();
            boolean scheduled = SyncJob.schedule(this, ok);
            toast(!ok ? "Background sync needs “Access data in the background” for Cipher Bridge in Health Connect."
                : scheduled ? "Background sync on: every hour on Wi-Fi when your Mac is reachable." : "Android didn’t allow the background job. Try again later.");
        } else if (code == REQ_LOCATION) {
            File file = pendingLocation; pendingLocation = null;
            boolean any = false; for (int g : granted) any |= g == PackageManager.PERMISSION_GRANTED;
            if (any && file != null) captureLocation(file);
            else if (!any) { prefs.edit().putBoolean("urgeLocation", false).apply(); toast("Location off. Turn it on in the Urge sheet any time."); }
        } else if (code == REQ_SPOT_FINE) {
            if (checkSelfPermission(FINE) == PackageManager.PERMISSION_GRANTED) askSpotPermissions();
            else toast("Spots need precise location. You can allow it in Settings → Spots.");
        } else if (code == REQ_BACKGROUND_LOCATION) {
            SpotReceiver.register(this);
            toast(SpotReceiver.canWatch(this) ? "Spots are on: you'll get a quick check-in when you arrive." : "Spots need location “Allow all the time”. You can change it in Settings → Spots.");
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
        toast("Looking for Cipher on your Wi-Fi…");
        engine.discover(list -> {
            if (list.isEmpty()) { SyncEngine.RUNNING.set(false); toast("No Mac found. Open Cipher on your Mac and keep both devices on the same Wi-Fi."); return; }
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
            finishPairing("Couldn’t reach your Mac. Keep Cipher open on the Mac and both devices on the same Wi-Fi.");
        }
    }
    void finishPairing(String message) { runUi(() -> { SyncEngine.RUNNING.set(false); toast(message); render(); }); }
    void forget() {
        dialog().setTitle("Forget " + engine.macName() + "?")
            .setMessage("This phone stops sending to that Mac until you pair again. Also choose Forget on the Mac (Health). Anything waiting stays on this phone.")
            .setPositiveButton("Forget", (d, w) -> {
                prefs.edit().remove("key").remove("macName").remove("service").putBoolean("backgroundSync", false).putBoolean("screenTimeBackground",false).apply();
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
            if (result != RESULT_OK || capture == null || capture.length() == 0) {
                if (capture != null) capture.delete();
                // Backing out of "Add photo" returns to the meal so far rather than leaving it unfinished.
                File open = photoMode.equals("mealMore") ? openMeal() : null;
                if (open != null) askMealNote(open);
                return;
            }
            long now = System.currentTimeMillis();
            if (photoMode.equals("med")) { network.execute(() -> importMedPhotos(List.of(() -> new FileInputStream(capture)), List.of(now), capture)); return; }
            boolean more = photoMode.equals("mealMore");
            network.execute(() -> addMealPhotos(List.of(() -> new FileInputStream(capture)), List.of(now), more, capture));
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
            if (uris.size() == 1) {
                Uri uri = uris.get(0); long taken = dateTaken(uri);
                network.execute(() -> addMealPhotos(List.of(() -> getContentResolver().openInputStream(uri)), List.of(taken), false, null));
                return;
            }
            Runnable oneMeal = () -> {
                List<Uri> ordered = new ArrayList<>(uris);
                Map<Uri, Long> taken = new HashMap<>();
                for (Uri uri : ordered) taken.put(uri, dateTaken(uri));
                ordered.sort(Comparator.comparing(taken::get));
                List<SyncEngine.Source> sources = new ArrayList<>(); List<Long> times = new ArrayList<>();
                for (Uri uri : ordered) { sources.add(() -> getContentResolver().openInputStream(uri)); times.add(taken.get(uri)); }
                network.execute(() -> addMealPhotos(sources, times, false, null));
            };
            dialog().setTitle("Are these " + uris.size() + " photos one meal?")
                .setMessage("Choose One meal for photos of the same plate, such as each food added on a kitchen scale. Claude counts every food once.")
                .setPositiveButton("One meal", (d, w) -> oneMeal.run())
                .setNegativeButton("Separate", (d, w) -> askNote(note -> { for (Uri uri : uris) { long taken = dateTaken(uri); network.execute(() -> importMeal(() -> getContentResolver().openInputStream(uri), taken, note, null)); } }))
                .setCancelable(false).show();
        }
    }
    /** The meal still being photographed, if any. */
    File openMeal() {
        for (File meta : engine.queuedMeals()) {
            try { if (SyncEngine.readJSON(meta).optBoolean("open")) return meta; } catch (Exception ignored) {}
        }
        return null;
    }
    /**
     * Adds photos to a meal that stays open (not sent) until its note is saved: the open meal when `more`, otherwise a new
     * one, finishing any meal left open earlier. Then asks for the note, offering another photo. Blocking: call off the main thread.
     */
    void addMealPhotos(List<SyncEngine.Source> sources, List<Long> times, boolean more, File cleanup) {
        try {
            File meta = more ? openMeal() : null;
            if (!more) for (File stale = openMeal(); stale != null; stale = openMeal()) closeMeal(stale, null);
            JSONObject m;
            if (meta == null) {
                String id = UUID.randomUUID().toString();
                m = new JSONObject().put("id", id).put("takenAt", times.get(0) / 1000).put("note", "").put("photos", new JSONArray()).put("open", true);
                meta = new File(engine.mealsDir(), id + ".json");
            } else m = SyncEngine.readJSON(meta);
            JSONArray photos = m.getJSONArray("photos");
            int failed = 0;
            for (int i = 0; i < sources.size() && photos.length() < SyncEngine.MAX_MEAL_PHOTOS; i++) {
                // A meal's only photo shares its ID, so a single-photo meal syncs exactly as before.
                String id = photos.length() == 0 ? m.getString("id") : UUID.randomUUID().toString();
                try { SyncEngine.writeUpright(sources.get(i), new File(engine.mealsDir(), id + ".jpg")); photos.put(id); }
                catch (Exception e) { failed++; }
            }
            if (cleanup != null) cleanup.delete();
            if (photos.length() == 0) { runUi(() -> toast("That photo couldn’t be read. Try another one.")); return; }
            try (FileOutputStream out = new FileOutputStream(meta)) { out.write(SyncEngine.bytes(m)); }
            File saved = meta; int skipped = failed;
            runUi(() -> { if (skipped > 0) toast(skipped == 1 ? "One photo couldn’t be read." : skipped + " photos couldn’t be read."); render(); askMealNote(saved); });
        } catch (Exception e) {
            if (cleanup != null) cleanup.delete();
            runUi(() -> toast("That photo couldn’t be read. Try another one."));
        }
    }
    /** Asks what's in the open meal, with Add photo for the next step on the scale. Save or Skip queues it to send. */
    void askMealNote(File meta) {
        JSONObject m;
        try { m = SyncEngine.readJSON(meta); } catch (Exception e) { return; }
        int count = SyncEngine.mealPhotos(m).size();
        EditText field = new EditText(this);
        field.setHint("e.g. 2 rotis, dal (optional)"); field.setSingleLine(false); field.setTextColor(Ui.TEXT); field.setHintTextColor(Ui.FAINT);
        field.setText(m.optString("note"));
        FrameLayout wrap = new FrameLayout(this); ui.pad(wrap, 20, 8, 20, 0); wrap.addView(field);
        AlertDialog.Builder builder = dialog().setTitle("What’s in it?").setView(wrap)
            .setMessage(count == 1 ? "Adding more food on the scale? Tap Add photo after each addition; Claude counts every food once."
                : count + " photos · one meal")
            .setPositiveButton("Save", (d, w) -> { closeMeal(meta, field.getText().toString().trim()); toast("Meal saved"); render(); sync(false, true); })
            .setNegativeButton("Skip", (d, w) -> { closeMeal(meta, ""); toast("Meal saved"); render(); sync(false, true); })
            .setCancelable(false);
        if (count < SyncEngine.MAX_MEAL_PHOTOS) builder.setNeutralButton("Add photo", (d, w) -> {
            saveMealNote(meta, field.getText().toString().trim());
            photoMode = "mealMore"; takePhoto();
        });
        builder.show();
    }
    void saveMealNote(File meta, String note) {
        try {
            JSONObject m = SyncEngine.readJSON(meta).put("note", note.length() > 500 ? note.substring(0, 500) : note);
            try (FileOutputStream out = new FileOutputStream(meta)) { out.write(SyncEngine.bytes(m)); }
        } catch (Exception ignored) {}
    }
    /** Marks a meal ready to send, keeping its note when `note` is null. */
    void closeMeal(File meta, String note) {
        try {
            JSONObject m = SyncEngine.readJSON(meta);
            if (note != null) m.put("note", note.length() > 500 ? note.substring(0, 500) : note);
            m.remove("open");
            try (FileOutputStream out = new FileOutputStream(meta)) { out.write(SyncEngine.bytes(m)); }
        } catch (Exception ignored) {}
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
