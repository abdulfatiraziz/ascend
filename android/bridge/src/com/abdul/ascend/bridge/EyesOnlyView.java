package com.abdul.ascend.bridge;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.animation.AccelerateInterpolator;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Eyes only, as on the Mac: a gold iris closes over the app onto a safe dial. The fingerprint (or the phone's
 * PIN) spins the dial, stamps CLEARED and opens the iris. With animations off, the moves are skipped.
 */
final class EyesOnlyView extends FrameLayout {
    enum Phase { SEALING, SEALED, CHECKING, DENIED, CLEARED }

    private final Ui ui;
    private final Runnable onUnlock, onOpen;
    private final boolean still;
    private Phase phase = Phase.SEALING;
    private float iris = 1f;               // 1 = hole fills the screen (app visible), 0 = closed
    private final Paint clear = new Paint(Paint.ANTI_ALIAS_FLAG), ring = new Paint(Paint.ANTI_ALIAS_FLAG), felt = new Paint();
    private final LinearLayout card;
    private final Dial dial;
    private final ImageView glyph;
    private final TextView caption, stamp, title, body;
    private final Rule left, right;
    private final Button button;
    private ValueAnimator pulse;

    EyesOnlyView(Context c, Ui ui, Runnable onUnlock, Runnable onOpen) {
        super(c);
        this.ui = ui; this.onUnlock = onUnlock; this.onOpen = onOpen;
        still = Settings.Global.getFloat(c.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f;
        setWillNotDraw(false);
        setClickable(true); setFocusable(true);          // nothing behind the cover takes a touch
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
        setLayerType(LAYER_TYPE_HARDWARE, null);
        clear.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));
        ring.setStyle(Paint.Style.STROKE); ring.setStrokeWidth(ui.dp(3)); ring.setColor(Ui.ACCENT);
        ring.setShadowLayer(ui.dp(12), 0, 0, 0xCCF0D49A);

        card = ui.column(14); card.setGravity(Gravity.CENTER_HORIZONTAL);
        ui.pad(card, 26, 30, 26, 28);
        caption = ui.mono("", 9, Ui.GOLD_DIM); caption.setLetterSpacing(0.25f); caption.setGravity(Gravity.CENTER);
        LinearLayout stampRow = ui.row(10); stampRow.setGravity(Gravity.CENTER);
        left = new Rule(c, true); right = new Rule(c, false);
        stamp = new TextView(c); stamp.setTypeface(Ui.serif(600)); stamp.setTextSize(21); stamp.setLetterSpacing(0.33f); stamp.setIncludeFontPadding(false);
        stampRow.addView(left, new LinearLayout.LayoutParams(ui.dp(44), ui.dp(8)));
        stampRow.addView(stamp);
        stampRow.addView(right, new LinearLayout.LayoutParams(ui.dp(44), ui.dp(8)));
        LinearLayout stampBlock = ui.column(9); stampBlock.setGravity(Gravity.CENTER_HORIZONTAL);
        stampBlock.addView(caption); stampBlock.addView(stampRow);
        card.addView(stampBlock);

        FrameLayout dialBox = new FrameLayout(c);
        dial = new Dial(c);
        dialBox.addView(dial, new FrameLayout.LayoutParams(ui.dp(120), ui.dp(120), Gravity.CENTER));
        glyph = new ImageView(c);
        dialBox.addView(glyph, new FrameLayout.LayoutParams(ui.dp(40), ui.dp(40), Gravity.CENTER));
        card.addView(dialBox, new LinearLayout.LayoutParams(ui.dp(120), ui.dp(120)));

        title = ui.text("", 28, Ui.TEXT, 600); title.setGravity(Gravity.CENTER);
        body = ui.text("", 12.5f, Ui.MUTED, 400); body.setGravity(Gravity.CENTER);
        card.addView(title); card.addView(body);
        button = ui.pill("Unlock with fingerprint", v -> unlock());
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(Ui.WRAP, ui.dp(44)); bp.topMargin = ui.dp(4);
        card.addView(button, bp);

        int width = Math.min(c.getResources().getDisplayMetrics().widthPixels - ui.dp(32), ui.dp(420));
        addView(card, new FrameLayout.LayoutParams(width, Ui.WRAP, Gravity.CENTER));
        show(Phase.SEALING);
    }

    // MARK: Phases

    private void show(Phase p) {
        phase = p;
        boolean cleared = p == Phase.CLEARED, denied = p == Phase.DENIED;
        int color = cleared ? Ui.LAMP : denied ? Ui.RED : Ui.ACCENT;
        caption.setText(cleared ? "FILE 0075 · ACCESS GRANTED" : denied ? "FILE 0075 · NOT RECOGNISED" : "FILE 0075 · CLEARANCE REQUIRED");
        stamp.setText(cleared ? "CLEARED" : denied ? "ACCESS DENIED" : "EYES ONLY");
        stamp.setTextSize(denied ? 17 : 21);
        stamp.setTextColor(color); left.color = color; right.color = color; left.invalidate(); right.invalidate();
        glyph.setImageDrawable(ui.icon(cleared ? "ic_lock_open" : "ic_fingerprint", denied ? Ui.RED : cleared ? Ui.LAMP : Ui.ACCENT));
        title.setText(cleared ? "Welcome back, Abdul." : "Ascend is sealed.");
        body.setText(denied ? "Not recognised. Try again." : "Numbers, photos and logs are hidden until your fingerprint or phone PIN opens it.");
        body.setTextColor(denied ? Ui.RED : Ui.MUTED);
        card.setBackground(ui.round(Ui.PANEL, 16, ((cleared ? Ui.LAMP : Ui.ACCENT) & 0x00FFFFFF) | 0x59000000, 1));
        button.setEnabled(p != Phase.CHECKING && p != Phase.CLEARED);
        button.setAlpha(button.isEnabled() ? 1f : 0.5f);
        setContentDescription(title.getText() + " " + body.getText());
        if (p == Phase.CHECKING && !still) {
            pulse = ValueAnimator.ofFloat(1f, 0.35f); pulse.setDuration(600); pulse.setRepeatMode(ValueAnimator.REVERSE); pulse.setRepeatCount(ValueAnimator.INFINITE);
            pulse.addUpdateListener(a -> glyph.setAlpha((float) a.getAnimatedValue())); pulse.start();
        } else if (pulse != null) { pulse.cancel(); pulse = null; glyph.setAlpha(1f); }
    }

    /** The iris closes and the card settles onto the felt. */
    void seal() {
        if (still) { iris = 0; card.setAlpha(1); show(Phase.SEALED); invalidate(); return; }
        card.setAlpha(0); card.setScaleX(0.92f); card.setScaleY(0.92f);
        animate(1f, 0f, 700, new AccelerateDecelerateInterpolator(), v -> { iris = v; invalidate(); });
        animate(0f, -180f, 1100, new DecelerateInterpolator(), v -> dial.setRotation(v));
        postDelayed(() -> {
            show(Phase.SEALED);
            card.animate().alpha(1).scaleX(1).scaleY(1).setDuration(400).setInterpolator(new OvershootInterpolator(1.4f)).start();
        }, 550);
    }

    /** Already sealed, no animation: used when the app opens or comes back locked. */
    void sealedNow() { iris = 0; card.setAlpha(1); card.setScaleX(1); card.setScaleY(1); dial.setRotation(-180); show(Phase.SEALED); invalidate(); }

    void unlock() {
        if (phase == Phase.CHECKING || phase == Phase.CLEARED) return;
        show(Phase.CHECKING);
        onUnlock.run();
    }

    /** The prompt was closed without an answer: stay sealed, ready to try again. */
    void cancelled() { if (phase == Phase.CHECKING) show(Phase.SEALED); }

    void denied() {
        show(Phase.DENIED);
        if (still) return;
        float[] xs = {14, -12, 9, -6, 3, 0};
        for (int i = 0; i < xs.length; i++) { float x = ui.dp(xs[i]); postDelayed(() -> card.animate().translationX(x).setDuration(60).start(), i * 60L); }
    }

    void cleared() {
        if (still) { onOpen.run(); return; }
        show(Phase.CLEARED);
        card.setScaleX(0.96f); card.setScaleY(0.96f);
        card.animate().scaleX(1).scaleY(1).setDuration(350).setInterpolator(new OvershootInterpolator(2.5f)).start();
        animate(0f, 1f, 700, new DecelerateInterpolator(), v -> { dial.progress = v; dial.invalidate(); });
        float from = dial.getRotation();
        animate(from, from + 360f, 900, new AccelerateDecelerateInterpolator(), v -> dial.setRotation(v));
        postDelayed(() -> animate(0f, 1f, 750, new AccelerateInterpolator(), v -> { iris = v; invalidate(); }), 850);
        postDelayed(onOpen, 1650);
    }

    private interface Step { void at(float v); }
    private void animate(float from, float to, long ms, android.animation.TimeInterpolator curve, Step step) {
        ValueAnimator a = ValueAnimator.ofFloat(from, to); a.setDuration(ms); a.setInterpolator(curve);
        a.addUpdateListener(x -> step.at((float) x.getAnimatedValue())); a.start();
    }

    // MARK: Drawing

    /** Lit felt, the card, then the iris hole cut through both; the gold ring sits on the hole's edge. */
    @Override protected void dispatchDraw(Canvas canvas) {
        int w = getWidth(), h = getHeight();
        int save = canvas.saveLayer(0, 0, w, h, null);
        felt.setShader(new RadialGradient(w * 0.5f, h * 0.4f, ui.dp(520), new int[]{0xFF13493A, Ui.BG, 0xFF061A14}, new float[]{0, 0.55f, 1}, Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, w, h, felt);
        felt.setShader(new RadialGradient(w * 0.3f, 0, ui.dp(360), new int[]{0x29F0D49A, 0x00F0D49A}, null, Shader.TileMode.CLAMP));
        canvas.drawRect(0, 0, w, h, felt);
        felt.setShader(new LinearGradient(0, h * 0.5f, 0, h, 0x00000000, 0x59000000, Shader.TileMode.CLAMP));
        canvas.drawRect(0, h * 0.5f, w, h, felt);
        felt.setShader(null);
        super.dispatchDraw(canvas);
        float full = (float) Math.hypot(w, h) + ui.dp(40);
        if (iris > 0.001f) canvas.drawCircle(w / 2f, h / 2f, full * iris / 2f, clear);
        canvas.restoreToCount(save);
        if (iris > 0.001f && iris < 0.999f) canvas.drawCircle(w / 2f, h / 2f, full * iris / 2f, ring);
    }

    /** A watch bezel: 60 minute ticks and a gold arc that fills when cleared. */
    private final class Dial extends View {
        float progress = 0;
        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        Dial(Context c) { super(c); }
        @Override protected void onDraw(Canvas c) {
            float s = Math.min(getWidth(), getHeight()), r = s / 2f, lw = ui.dp(3), cx = getWidth() / 2f, cy = getHeight() / 2f;
            p.setStyle(Paint.Style.FILL);
            for (int i = 0; i < 60; i++) {
                boolean major = i % 5 == 0;
                p.setColor(major ? 0x73F1E8D4 : 0x29F1E8D4);
                float tw = ui.dp(major ? 1.5f : 1f), th = ui.dp(major ? 7 : 4), top = cy - (r - lw - ui.dp(7)) - th / 2f;
                c.save(); c.rotate(i * 6, cx, cy); c.drawRect(cx - tw / 2f, top, cx + tw / 2f, top + th, p); c.restore();
            }
            p.setStyle(Paint.Style.STROKE); p.setStrokeWidth(lw); p.setStrokeCap(Paint.Cap.ROUND);
            RectF box = new RectF(cx - r + lw / 2f, cy - r + lw / 2f, cx + r - lw / 2f, cy + r - lw / 2f);
            p.setColor(0x14F1E8D4); c.drawOval(box, p);
            p.setColor(Ui.LAMP); c.drawArc(box, -90, 360 * Math.max(0.001f, Math.min(1, progress)), false, p);
        }
    }

    /** A hairline fading in towards the stamp, ending in a small diamond. */
    private final class Rule extends View {
        final boolean leading; int color = Ui.ACCENT;
        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        Rule(Context c, boolean leading) { super(c); this.leading = leading; }
        @Override protected void onDraw(Canvas c) {
            float w = getWidth(), cy = getHeight() / 2f, d = ui.dp(3.5f), lineEnd = leading ? w - d * 2.2f : d * 2.2f;
            int solid = (color & 0x00FFFFFF) | 0xCC000000, none = color & 0x00FFFFFF;
            p.setShader(leading ? new LinearGradient(0, 0, lineEnd, 0, none, solid, Shader.TileMode.CLAMP) : new LinearGradient(lineEnd, 0, w, 0, solid, none, Shader.TileMode.CLAMP));
            p.setStyle(Paint.Style.FILL);
            c.drawRect(leading ? 0 : lineEnd, cy - 0.5f * getResources().getDisplayMetrics().density, leading ? lineEnd : w, cy + 0.5f * getResources().getDisplayMetrics().density, p);
            p.setShader(null); p.setColor(color);
            float dx = leading ? w - d : d;
            c.save(); c.rotate(45, dx, cy); c.drawRect(dx - d / 2f, cy - d / 2f, dx + d / 2f, cy + d / 2f, p); c.restore();
        }
    }
}
