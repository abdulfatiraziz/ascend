package com.abdul.ascend.bridge;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;

/** The Ascend look on Android: the Mac app's dark palette, one type scale, rounded cards. Plain views, no libraries. */
final class Ui {
    static final int BG = 0xFF0D0C10, PANEL = 0xFF16141B, PANEL2 = 0xFF221F2A, NAV = 0xFF121016, LINE = 0x17FFFFFF;
    static final int TEXT = 0xFFF2F0F5, SOFT = 0xFFD9D5E0, MUTED = 0xFFA39DAD, FAINT = 0xFF6F6878;
    static final int ACCENT = 0xFFA18AFF, ACCENT_TEXT = 0xFFC2B4FF, ACCENT_SOFT = 0x2EA18AFF, ON_ACCENT = 0xFF120F1A;
    static final int ORANGE = 0xFFF0A35E, GREEN = 0xFF7FD6A4, RED = 0xFFF49A90;
    static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT, WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;
    final Context c;
    final float density;
    Ui(Context c) { this.c = c; density = c.getResources().getDisplayMetrics().density; }

    int dp(float v) { return Math.round(v * density); }
    static Typeface weight(int w) { return Typeface.create(Typeface.DEFAULT, w, false); }

    GradientDrawable round(int fill, float radius, int stroke, float strokeWidth) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(fill); d.setCornerRadius(dp(radius));
        if (strokeWidth > 0) d.setStroke(Math.max(1, dp(strokeWidth)), stroke);
        return d;
    }
    GradientDrawable dashed(int fill, float radius, int stroke) {
        GradientDrawable d = round(fill, radius, stroke, 1);
        d.setStroke(dp(1), stroke, dp(6), dp(4));
        return d;
    }

    TextView text(String s, float sp, int color, int weight) {
        TextView t = new TextView(c);
        t.setText(s); t.setTextSize(sp); t.setTextColor(color); t.setTypeface(weight(weight)); t.setIncludeFontPadding(false);
        t.setLineSpacing(0, 1.15f);
        return t;
    }
    TextView body(String s) { return text(s, 14, SOFT, 400); }
    TextView small(String s) { return text(s, 12, MUTED, 400); }
    TextView kicker(String s) {
        TextView t = text(s.toUpperCase(), 11, MUTED, 600);
        t.setLetterSpacing(0.12f);
        return t;
    }
    TextView title(String s) { TextView t = text(s, 28, TEXT, 700); t.setLetterSpacing(-0.02f); return t; }
    TextView mono(String s, float sp, int color) { TextView t = text(s, sp, color, 500); t.setTypeface(Typeface.MONOSPACE); return t; }
    TextView oneLine(TextView t) { t.setMaxLines(1); t.setEllipsize(TextUtils.TruncateAt.END); return t; }

    LinearLayout column(int gap) {
        LinearLayout l = new LinearLayout(c); l.setOrientation(LinearLayout.VERTICAL);
        if (gap > 0) { l.setShowDividers(LinearLayout.SHOW_DIVIDER_MIDDLE); l.setDividerDrawable(spacer(0, gap)); }
        return l;
    }
    LinearLayout row(int gap) {
        LinearLayout l = new LinearLayout(c); l.setOrientation(LinearLayout.HORIZONTAL); l.setGravity(Gravity.CENTER_VERTICAL);
        if (gap > 0) { l.setShowDividers(LinearLayout.SHOW_DIVIDER_MIDDLE); l.setDividerDrawable(spacer(gap, 0)); }
        return l;
    }
    private GradientDrawable spacer(int w, int h) { GradientDrawable d = new GradientDrawable(); d.setColor(0); d.setSize(dp(w), dp(h)); return d; }
    LinearLayout card(int gap) {
        LinearLayout l = column(gap);
        l.setBackground(round(PANEL, 18, LINE, 1)); l.setPadding(dp(16), dp(16), dp(16), dp(16));
        return l;
    }
    /** A row of equal-width children. */
    LinearLayout grid(int gap, View... items) {
        LinearLayout r = row(gap); r.setGravity(Gravity.TOP);
        for (View v : items) r.addView(v, new LinearLayout.LayoutParams(0, WRAP, 1));
        return r;
    }
    static LinearLayout.LayoutParams wide() { return new LinearLayout.LayoutParams(MATCH, WRAP); }
    LinearLayout.LayoutParams size(int w, int h) { return new LinearLayout.LayoutParams(w < 0 ? w : dp(w), h < 0 ? h : dp(h)); }

    Drawable icon(String name, int color) {
        int id = c.getResources().getIdentifier(name, "drawable", c.getPackageName());
        Drawable d = c.getDrawable(id).mutate(); d.setTint(color);
        return d;
    }
    ImageView iconView(String name, int color, int size) {
        ImageView v = new ImageView(c); v.setImageDrawable(icon(name, color));
        v.setLayoutParams(new LinearLayout.LayoutParams(dp(size), dp(size)));
        return v;
    }
    /** An icon centred in a filled circle. */
    FrameLayout badge(String name, int fill, int color, int size, int iconSize) {
        FrameLayout f = new FrameLayout(c); f.setBackground(round(fill, size / 2f, 0, 0));
        ImageView i = new ImageView(c); i.setImageDrawable(icon(name, color));
        f.addView(i, new FrameLayout.LayoutParams(dp(iconSize), dp(iconSize), Gravity.CENTER));
        f.setLayoutParams(new LinearLayout.LayoutParams(dp(size), dp(size)));
        return f;
    }

    private Button base(String label, int fill, int textColor, int stroke, float height, float radius, float sp) {
        Button b = new Button(c);
        b.setText(label); b.setAllCaps(false); b.setTextSize(sp); b.setTextColor(textColor); b.setTypeface(weight(600));
        b.setBackground(round(fill, radius, stroke, stroke == 0 ? 0 : 1.5f)); b.setStateListAnimator(null);
        b.setMinHeight(dp(height)); b.setMinimumHeight(dp(height)); b.setPadding(dp(16), 0, dp(16), 0);
        b.setGravity(Gravity.CENTER);
        return b;
    }
    Button primary(String label, View.OnClickListener l) { Button b = base(label, ACCENT, ON_ACCENT, 0, 52, 16, 15); b.setOnClickListener(tap(l)); return b; }
    Button secondary(String label, View.OnClickListener l) { Button b = base(label, PANEL, TEXT, 0x1FFFFFFF, 48, 14, 14); b.setOnClickListener(tap(l)); return b; }
    Button outline(String label, View.OnClickListener l) { Button b = base(label, 0, ACCENT_TEXT, ACCENT, 44, 22, 13); b.setOnClickListener(tap(l)); return b; }
    Button danger(String label, View.OnClickListener l) { Button b = base(label, 0, RED, 0x80F0786E, 52, 16, 15); b.setOnClickListener(tap(l)); return b; }
    Button chip(String label, boolean on, View.OnClickListener l) {
        Button b = base(label, on ? ACCENT_SOFT : PANEL2, on ? 0xFFE0D8FF : TEXT, on ? ACCENT : 0, 36, 18, 13);
        b.setPadding(dp(14), 0, dp(14), 0); b.setOnClickListener(tap(l));
        return b;
    }
    /** A filled pill, for actions inside cards such as Taken. */
    Button pill(String label, View.OnClickListener l) { Button b = base(label, ACCENT, ON_ACCENT, 0, 44, 22, 14); b.setOnClickListener(tap(l)); return b; }
    /** A button with an icon and label centred together. */
    LinearLayout iconButton(String label, String icon, Drawable background, int color, float height, View.OnClickListener l) {
        LinearLayout b = row(10); b.setGravity(Gravity.CENTER);
        b.setBackground(background);
        b.addView(iconView(icon, color, 20));
        b.addView(text(label, 15, color, 600));
        b.setMinimumHeight(dp(height)); b.setClickable(true); b.setContentDescription(label);
        b.setOnClickListener(tap(l));
        return b;
    }
    View divider() { View v = new View(c); v.setBackgroundColor(0x0FFFFFFF); v.setLayoutParams(new LinearLayout.LayoutParams(MATCH, 1)); return v; }
    /** Click with a light key tick. */
    static View.OnClickListener tap(View.OnClickListener l) {
        return v -> { v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); l.onClick(v); };
    }
    /** A 4dp progress bar filled to `fraction`. */
    View bar(double fraction, int color) {
        FrameLayout track = new FrameLayout(c); track.setBackground(round(0x14FFFFFF, 2, 0, 0));
        View fill = new View(c); fill.setBackground(round(color, 2, 0, 0));
        track.addView(fill, new FrameLayout.LayoutParams(0, MATCH));
        track.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            int w = (int) Math.round((r - l) * Math.max(0, Math.min(1, fraction)));
            if (fill.getLayoutParams().width != w) { fill.getLayoutParams().width = w; fill.post(fill::requestLayout); }
        });
        track.setLayoutParams(new LinearLayout.LayoutParams(MATCH, dp(4)));
        return track;
    }
    void pad(View v, int l, int t, int r, int b) { v.setPadding(dp(l), dp(t), dp(r), dp(b)); }
    static ColorStateList tint(int on, int off) {
        return new ColorStateList(new int[][]{{android.R.attr.state_checked}, {}}, new int[]{on, off});
    }
}
