package com.abdul.ascend.bridge;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.drawable.Icon;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/**
 * Medicine reminders. The Mac sends the next 14 days of scheduled doses with every reply; this sets an exact
 * alarm for each one not yet taken, shows a notification with a Taken button at that time, and re-arms after a
 * reboot. A Taken tap is queued like an urge and goes to the Mac with the next send.
 */
public final class ReminderReceiver extends BroadcastReceiver {
    static final String CHANNEL = "medicines";
    static final String REMIND = "com.abdul.ascend.bridge.REMIND", TAKEN = "com.abdul.ascend.bridge.TAKEN";

    @Override public void onReceive(Context context, Intent intent) {
        String action = intent.getAction() == null ? "" : intent.getAction();
        try {
            if (action.equals(REMIND)) {
                JSONObject dose = find(context, intent.getStringExtra("key"));
                if (dose != null && !taken(context, dose)) notify(context, dose);
            } else if (action.equals(TAKEN)) {
                JSONObject dose = find(context, intent.getStringExtra("key"));
                if (dose != null) record(context, dose, true);
                context.getSystemService(NotificationManager.class).cancel(code(intent.getStringExtra("key")));
            } else schedule(context); // boot, app update, clock or time zone change
        } catch (Exception ignored) {}
    }

    static SharedPreferences prefs(Context c) { return c.getSharedPreferences("link", Context.MODE_PRIVATE); }
    static String key(JSONObject dose) { return dose.optString("medID") + "|" + dose.optString("day") + "|" + dose.optInt("minute"); }
    static int code(String key) { return key == null ? 0 : key.hashCode(); }
    static JSONArray schedule(SharedPreferences p) {
        try { return new JSONArray(p.getString("medSchedule", "[]")); } catch (JSONException e) { return new JSONArray(); }
    }
    static JSONObject find(Context c, String key) {
        JSONArray all = schedule(prefs(c));
        for (int i = 0; i < all.length(); i++) { JSONObject d = all.optJSONObject(i); if (d != null && key(d).equals(key)) return d; }
        return null;
    }
    static File dosesDir(Context c) { File dir = new File(c.getFilesDir(), "doses"); dir.mkdirs(); return dir; }
    static File[] queuedDoses(Context c) {
        File[] files = dosesDir(c).listFiles((d, n) -> n.endsWith(".json"));
        if (files == null) return new File[0];
        Arrays.sort(files, Comparator.comparingLong(File::lastModified));
        return files;
    }
    /** Taken state including taps not yet sent to the Mac; the latest tap wins. */
    static boolean taken(Context c, JSONObject dose) {
        boolean result = dose.optBoolean("taken");
        String key = key(dose);
        for (File f : queuedDoses(c)) {
            try (InputStream in = new FileInputStream(f)) {
                JSONObject q = new JSONObject(new String(in.readAllBytes(), StandardCharsets.UTF_8));
                if (key(q).equals(key)) result = q.optBoolean("taken");
            } catch (Exception ignored) {}
        }
        return result;
    }
    /** Queues a Taken (or undo) tap for the Mac and updates reminders. */
    static void record(Context c, JSONObject dose, boolean taken) throws Exception {
        JSONObject q = new JSONObject().put("id", UUID.randomUUID().toString()).put("medID", dose.getString("medID")).put("day", dose.getString("day"))
            .put("minute", dose.getInt("minute")).put("takenAt", System.currentTimeMillis() / 1000.0).put("taken", taken);
        try (OutputStream out = new FileOutputStream(new File(dosesDir(c), System.currentTimeMillis() + "-" + q.getString("id") + ".json"))) {
            out.write(q.toString().getBytes(StandardCharsets.UTF_8));
        }
        schedule(c);
    }
    /** Replaces every pending alarm with one per upcoming dose that isn't taken. */
    static void schedule(Context c) {
        SharedPreferences p = prefs(c);
        AlarmManager alarms = c.getSystemService(AlarmManager.class);
        for (String key : p.getStringSet("alarmKeys", new HashSet<>())) alarms.cancel(alarm(c, key));
        Set<String> keys = new HashSet<>();
        JSONArray all = schedule(p);
        long now = System.currentTimeMillis();
        for (int i = 0; i < all.length(); i++) {
            JSONObject d = all.optJSONObject(i);
            if (d == null) continue;
            long at = (long) (d.optDouble("at") * 1000);
            if (at <= now || taken(c, d)) continue;
            String key = key(d);
            if (alarms.canScheduleExactAlarms()) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm(c, key));
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm(c, key));
            keys.add(key);
        }
        p.edit().putStringSet("alarmKeys", keys).apply();
    }
    static PendingIntent alarm(Context c, String key) {
        Intent i = new Intent(c, ReminderReceiver.class).setAction(REMIND).putExtra("key", key);
        return PendingIntent.getBroadcast(c, code(key), i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
    static void notify(Context c, JSONObject dose) {
        NotificationManager manager = c.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL, "Medicine reminders", NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("At the times your doctor prescribed");
        manager.createNotificationChannel(channel);
        String key = key(dose);
        PendingIntent open = PendingIntent.getActivity(c, code(key), new Intent(c, BridgeActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE);
        PendingIntent take = PendingIntent.getBroadcast(c, code(key) + 1, new Intent(c, ReminderReceiver.class).setAction(TAKEN).putExtra("key", key),
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        String detail = dose.optString("detail");
        Notification n = new Notification.Builder(c, CHANNEL).setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("Time for " + dose.optString("name", "your medicine"))
            .setContentText(detail.isEmpty() ? "Tap Taken once you've had it." : detail)
            .setCategory(Notification.CATEGORY_REMINDER).setContentIntent(open).setAutoCancel(true)
            .addAction(new Notification.Action.Builder(Icon.createWithResource(c, android.R.drawable.checkbox_on_background), "Taken", take).build())
            .build();
        manager.notify(code(key), n);
    }
}
