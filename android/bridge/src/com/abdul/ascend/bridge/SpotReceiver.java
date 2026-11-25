package com.abdul.ascend.bridge;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.drawable.Icon;
import android.location.LocationManager;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.UUID;

/**
 * Saved spots. Android watches them with proximity alerts, so the app doesn't poll GPS. Arriving at one logs a
 * visit as an urge with no outcome yet and shows a neutral "Quick check-in?" notification with two buttons. An
 * answer updates that urge (on the Mac too, if it was already sent); no answer leaves it as an unanswered visit.
 * Spots and visits stay on this phone and the paired Mac.
 */
public final class SpotReceiver extends BroadcastReceiver {
    static final String CHANNEL = "checkins";
    static final String ARRIVE = "com.abdul.ascend.bridge.SPOT", ANSWER = "com.abdul.ascend.bridge.SPOT_ANSWER";
    static final float RADIUS_METRES = 60f;
    /** At most one check-in in this window across all spots, so walking in and out, or between nearby spots, doesn't repeat it. */
    static final long QUIET_MS = 45 * 60 * 1000L;

    @Override public void onReceive(Context c, Intent intent) {
        String action = intent.getAction() == null ? "" : intent.getAction();
        try {
            if (action.equals(ARRIVE)) {
                if (intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, false)) arrive(c, intent.getStringExtra("spot"));
            } else if (action.equals(ANSWER)) {
                answer(c, intent.getStringExtra("urge"), intent.getStringExtra("outcome"));
            } else register(c); // boot or app update
        } catch (Exception ignored) {}
    }

    static SharedPreferences prefs(Context c) { return c.getSharedPreferences("link", Context.MODE_PRIVATE); }
    static JSONArray spots(Context c) { try { return new JSONArray(prefs(c).getString("spots", "[]")); } catch (JSONException e) { return new JSONArray(); } }
    static JSONObject spot(Context c, String id) {
        JSONArray all = spots(c);
        for (int i = 0; i < all.length(); i++) { JSONObject s = all.optJSONObject(i); if (s != null && s.optString("id").equals(id)) return s; }
        return null;
    }
    static boolean canWatch(Context c) {
        return c.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            && c.checkSelfPermission(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }
    static PendingIntent arrival(Context c, String id) {
        Intent i = new Intent(c, SpotReceiver.class).setAction(ARRIVE).putExtra("spot", id);
        // Mutable so Android can add whether this is an arrival or a departure.
        return PendingIntent.getBroadcast(c, ("spot|" + id).hashCode(), i, PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
    /** Re-arms an alert for every saved spot. Safe to call often. */
    static void register(Context c) {
        LocationManager lm = c.getSystemService(LocationManager.class);
        JSONArray all = spots(c);
        for (int i = 0; i < all.length(); i++) {
            JSONObject s = all.optJSONObject(i);
            if (s == null) continue;
            try {
                lm.removeProximityAlert(arrival(c, s.optString("id")));
                if (canWatch(c)) lm.addProximityAlert(s.optDouble("latitude"), s.optDouble("longitude"), RADIUS_METRES, -1, arrival(c, s.optString("id")));
            } catch (SecurityException ignored) {}
        }
    }
    static JSONObject addSpot(Context c, double lat, double lon) throws JSONException {
        JSONArray all = spots(c);
        JSONObject s = new JSONObject().put("id", UUID.randomUUID().toString()).put("name", "Spot " + (all.length() + 1)).put("latitude", lat).put("longitude", lon);
        all.put(s);
        prefs(c).edit().putString("spots", all.toString()).apply();
        register(c);
        return s;
    }
    /** Replaces the spots that came from the Mac with the Mac's current list; spots saved on this phone stay. */
    static void mergeFromMac(Context c, JSONArray fromMac) {
        try {
            JSONArray all = spots(c), next = new JSONArray();
            for (int i = 0; i < all.length(); i++) { JSONObject s = all.optJSONObject(i); if (s != null && !s.optBoolean("mac")) next.put(s); }
            for (int i = 0; i < fromMac.length(); i++) {
                JSONObject m = fromMac.getJSONObject(i);
                next.put(new JSONObject().put("id", "mac-" + m.getString("id")).put("name", m.getString("name"))
                    .put("latitude", m.getDouble("latitude")).put("longitude", m.getDouble("longitude")).put("mac", true));
            }
            if (next.toString().equals(all.toString())) return;
            // Old Mac alerts are cleared before the list changes, since their IDs may be gone.
            LocationManager lm = c.getSystemService(LocationManager.class);
            for (int i = 0; i < all.length(); i++) { JSONObject s = all.optJSONObject(i); if (s != null && s.optBoolean("mac")) try { lm.removeProximityAlert(arrival(c, s.optString("id"))); } catch (SecurityException ignored) {} }
            prefs(c).edit().putString("spots", next.toString()).apply();
            register(c);
        } catch (JSONException ignored) {}
    }
    static void removeSpot(Context c, String id) {
        try { c.getSystemService(LocationManager.class).removeProximityAlert(arrival(c, id)); } catch (SecurityException ignored) {}
        JSONArray all = spots(c), kept = new JSONArray();
        for (int i = 0; i < all.length(); i++) { JSONObject s = all.optJSONObject(i); if (s != null && !s.optString("id").equals(id)) kept.put(s); }
        prefs(c).edit().putString("spots", kept.toString()).apply();
    }

    static File urgesDir(Context c) { File d = new File(c.getFilesDir(), "urges"); d.mkdirs(); return d; }
    static void write(File f, JSONObject j) throws Exception { try (OutputStream out = new FileOutputStream(f)) { out.write(SyncEngine.bytes(j)); } }

    static void arrive(Context c, String spotID) throws Exception {
        JSONObject s = spot(c, spotID);
        if (s == null) return;
        SharedPreferences p = prefs(c);
        long now = System.currentTimeMillis();
        // Shared across spots: nearby spots overlap, and one stop should ask once.
        if (now - p.getLong("spotLastAny", 0) < QUIET_MS) return;
        JSONObject urge = new JSONObject().put("id", UUID.randomUUID().toString()).put("takenAt", now / 1000).put("outcome", "Not recorded").put("note", "")
            .put("spot", s.optString("name")).put("latitude", s.optDouble("latitude")).put("longitude", s.optDouble("longitude"));
        write(new File(urgesDir(c), urge.getString("id") + ".json"), urge);
        // A copy, so a late answer can still be sent after the visit itself has synced.
        p.edit().putLong("spotLastAny", now).putString("visit|" + urge.getString("id"), urge.toString()).apply();
        notify(c, urge.getString("id"));
    }
    static PendingIntent answerIntent(Context c, String urgeID, String outcome) {
        Intent i = new Intent(c, SpotReceiver.class).setAction(ANSWER).putExtra("urge", urgeID).putExtra("outcome", outcome);
        return PendingIntent.getBroadcast(c, (urgeID + outcome).hashCode(), i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }
    static void notify(Context c, String urgeID) {
        NotificationManager m = c.getSystemService(NotificationManager.class);
        NotificationChannel ch = new NotificationChannel(CHANNEL, "Check-ins", NotificationManager.IMPORTANCE_DEFAULT);
        ch.setDescription("A quick check-in when you arrive at a saved spot");
        m.createNotificationChannel(ch);
        PendingIntent open = PendingIntent.getActivity(c, urgeID.hashCode(), new Intent(c, BridgeActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE);
        Notification publicVersion = new Notification.Builder(c, CHANNEL).setSmallIcon(android.R.drawable.ic_popup_reminder).setContentTitle("Cipher").build();
        Notification n = new Notification.Builder(c, CHANNEL).setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("Quick check-in?").setContentText("One tap.")
            .setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(publicVersion)
            .setContentIntent(open).setAutoCancel(true)
            .addAction(new Notification.Action.Builder(Icon.createWithResource(c, android.R.drawable.ic_menu_close_clear_cancel), "Acted on", answerIntent(c, urgeID, "Acted on it")).build())
            .addAction(new Notification.Action.Builder(Icon.createWithResource(c, android.R.drawable.checkbox_on_background), "Let it pass", answerIntent(c, urgeID, "Let it pass")).build())
            .build();
        m.notify(urgeID.hashCode(), n);
    }
    static void answer(Context c, String urgeID, String outcome) throws Exception {
        if (urgeID == null || outcome == null) return;
        c.getSystemService(NotificationManager.class).cancel(urgeID.hashCode());
        SharedPreferences p = prefs(c);
        File f = new File(urgesDir(c), urgeID + ".json");
        JSONObject urge = f.exists() ? SyncEngine.readJSON(f) : new JSONObject(p.getString("visit|" + urgeID, "{}"));
        if (!urge.has("id")) return;
        urge.put("outcome", outcome);
        write(f, urge); // re-queued: the Mac upgrades an unanswered visit with the same ID
        p.edit().remove("visit|" + urgeID).apply();
        try {
            JSONArray history = new JSONArray(p.getString("urgeHistory", "[]")), next = new JSONArray().put(new JSONObject().put("at", urge.optLong("takenAt") * 1000).put("outcome", outcome));
            for (int i = 0; i < Math.min(history.length(), 19); i++) next.put(history.get(i));
            p.edit().putString("urgeHistory", next.toString()).apply();
        } catch (JSONException ignored) {}
    }
}
