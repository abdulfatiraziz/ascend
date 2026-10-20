package com.abdul.ascend.bridge;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.OutcomeReceiver;
import android.health.connect.*;
import android.health.connect.datatypes.*;
import android.health.connect.datatypes.Record;
import org.json.*;
import java.io.*;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/**
 * Finding the Mac, reading Mi Fitness data from Health Connect and sending everything queued on this phone.
 * Shared by the app screen and the hourly background job, so both sync the same way.
 */
final class SyncEngine {
    static final String SOURCE = "com.xiaomi.wearable";
    static final String PREFIX = "android.permission.health.READ_";
    static final String BACKGROUND = "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND";
    static final String[] KEYS = {"heartRate","steps","sleep","oxygen","distance","activeEnergy","speed","elevation","workout"};
    static final String[] SUFFIXES = {"HEART_RATE","STEPS","SLEEP","OXYGEN_SATURATION","DISTANCE","ACTIVE_CALORIES_BURNED","SPEED","ELEVATION_GAINED","EXERCISE"};
    static final Class<?>[] TYPES = {HeartRateRecord.class,StepsRecord.class,SleepSessionRecord.class,OxygenSaturationRecord.class,DistanceRecord.class,ActiveCaloriesBurnedRecord.class,SpeedRecord.class,ElevationGainedRecord.class,ExerciseSessionRecord.class};
    static final String SERVICE = "_ascend-sync._tcp";
    static final int MAX_EDGE = 1568, MAX_MED_PHOTOS = 20;
    /** One sync at a time, whether started by the screen or the background job. */
    static final AtomicBoolean RUNNING = new AtomicBoolean();

    static final class Target {
        final String name; final InetAddress host; final int port;
        Target(String name, InetAddress host, int port) { this.name = name; this.host = host; this.port = port; }
    }
    static final class LinkError extends Exception { LinkError(String message) { super(message); } }
    /** Whether health reading may continue (foreground: screen open and unlocked; background: always). */
    interface Gate { boolean open(); }
    /** `snapshot` is null when nothing could be read; `problem` explains a partial or failed read. */
    interface HealthDone { void done(JSONObject snapshot, String problem); }
    interface Source { InputStream open() throws IOException; }

    final Context context;
    final SharedPreferences prefs;
    final HealthConnectManager manager;
    final Handler main;
    SyncEngine(Context context) {
        this.context = context;
        prefs = context.getSharedPreferences("link", Context.MODE_PRIVATE);
        manager = context.getSystemService(HealthConnectManager.class);
        main = new Handler(context.getMainLooper());
    }

    // MARK: State
    boolean paired() { return prefs.getString("key", null) != null; }
    String macName() { return prefs.getString("macName", "your Mac"); }
    String phoneID() {
        String id = prefs.getString("phoneID", null);
        if (id == null) { id = UUID.randomUUID().toString(); prefs.edit().putString("phoneID", id).apply(); }
        return id;
    }
    byte[] key() { return Base64.getDecoder().decode(prefs.getString("key", "")); }
    boolean allowed(int i) { return context.checkSelfPermission(PREFIX + SUFFIXES[i]) == PackageManager.PERMISSION_GRANTED; }
    int allowedCount() { int n = 0; for (int i = 0; i < KEYS.length; i++) if (allowed(i)) n++; return n; }
    boolean backgroundAllowed() { return context.checkSelfPermission(BACKGROUND) == PackageManager.PERMISSION_GRANTED; }
    static String[] healthPermissions() {
        String[] all = new String[SUFFIXES.length + 1];
        for (int i = 0; i < SUFFIXES.length; i++) all[i] = PREFIX + SUFFIXES[i];
        all[SUFFIXES.length] = BACKGROUND;
        return all;
    }
    JSONObject today() { try { return new JSONObject(prefs.getString("today", "{}")); } catch (JSONException e) { return new JSONObject(); } }
    JSONObject urgeCounts() { try { return new JSONObject(prefs.getString("urgeCounts", "{}")); } catch (JSONException e) { return new JSONObject(); } }

    // MARK: Queues
    File dir(String name) { File dir = new File(context.getFilesDir(), name); dir.mkdirs(); return dir; }
    static File[] json(File dir) {
        File[] files = dir.listFiles((d, n) -> n.endsWith(".json") && !n.equals("ready.json"));
        if (files == null) return new File[0];
        Arrays.sort(files, Comparator.comparingLong(File::lastModified));
        return files;
    }
    File mealsDir() { return dir("meals"); }
    File[] queuedMeals() { return json(mealsDir()); }
    File urgesDir() { return dir("urges"); }
    File[] queuedUrges() { return json(urgesDir()); }
    File medBatchesDir() { return dir("medbatches"); }
    File[] readyMedBatches() {
        File[] dirs = medBatchesDir().listFiles(f -> f.isDirectory() && new File(f, "ready.json").exists());
        return dirs == null ? new File[0] : dirs;
    }
    /** The batch being photographed now; created on first use and kept across camera round trips. */
    File openMedBatch() {
        String id = prefs.getString("medBatch", null);
        if (id == null) { id = UUID.randomUUID().toString(); prefs.edit().putString("medBatch", id).apply(); }
        File dir = new File(medBatchesDir(), id); dir.mkdirs(); return dir;
    }
    int readyMedPhotos() { int n = 0; for (File b : readyMedBatches()) n += json(b).length; return n; }
    File checkInsDir() { return dir("checkins"); }
    File[] queuedCheckIns() { return json(checkInsDir()); }
    /** Everything waiting on this phone for the Mac. */
    int waiting() { return queuedMeals().length + queuedUrges().length + ReminderReceiver.queuedDoses(context).length + readyMedPhotos() + queuedCheckIns().length; }
    /**
     * Queues a habit tick, number or clear for the Mac and applies it to the cached Today summary at once,
     * so the checklist and progress update before the next sync confirms them.
     */
    void recordCheckIn(JSONObject habit, String day, Boolean completed, Double value, boolean clear) throws Exception {
        JSONObject c = new JSONObject().put("id", UUID.randomUUID().toString()).put("habitID", habit.getString("id")).put("day", day);
        if (clear) c.put("clear", true); else if (value != null) c.put("value", value); else c.put("completed", completed);
        try (OutputStream out = new FileOutputStream(new File(checkInsDir(), System.currentTimeMillis() + "-" + c.getString("id") + ".json"))) { out.write(bytes(c)); }
        JSONObject today = today();
        JSONArray habits = today.optJSONArray("habits");
        if (habits == null) return;
        boolean was = habit.optBoolean("done"), now;
        if (clear) { now = false; habit.remove("value"); }
        else if (value != null) {
            habit.put("value", value);
            now = value >= habit.optDouble("minimum", Double.NEGATIVE_INFINITY) && value <= habit.optDouble("maximum", Double.POSITIVE_INFINITY);
        } else now = completed;
        habit.put("done", now);
        for (int i = 0; i < habits.length(); i++) if (habits.getJSONObject(i).optString("id").equals(habit.getString("id"))) habits.put(i, habit);
        int delta = (now ? 1 : 0) - (was ? 1 : 0);
        if (delta != 0 && !habit.optString("kind").equals("milestone")) {
            int done = today.optInt("habitsDone") + delta, due = today.optInt("habitsDue");
            today.put("habitsDone", done).put("progress", due == 0 ? 0 : (double) done / due)
                .put("toTarget", Math.max(0, (int) Math.ceil(due * today.optDouble("target", 0.75)) - done));
            JSONArray goals = today.optJSONArray("goals");
            if (goals != null) for (int i = 0; i < goals.length(); i++) {
                JSONObject g = goals.getJSONObject(i);
                if (g.optString("title").equals(habit.optString("goal"))) g.put("done", g.optInt("done") + delta);
            }
        }
        prefs.edit().putString("today", today.toString()).apply();
    }

    // MARK: Discovery
    /** Finds Ascend on this Wi-Fi via DNS-SD and resolves each Mac to a local address. Calls back on the main thread. */
    void discover(Consumer<List<Target>> done) {
        NsdManager nsd = context.getSystemService(NsdManager.class);
        Map<String, NsdServiceInfo> found = new LinkedHashMap<>();
        NsdManager.DiscoveryListener listener = new NsdManager.DiscoveryListener() {
            public void onDiscoveryStarted(String type) {}
            public void onDiscoveryStopped(String type) {}
            public void onStartDiscoveryFailed(String type, int error) {}
            public void onStopDiscoveryFailed(String type, int error) {}
            public void onServiceFound(NsdServiceInfo info) { main.post(() -> found.putIfAbsent(info.getServiceName(), info)); }
            public void onServiceLost(NsdServiceInfo info) {}
        };
        try { nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, listener); }
        catch (Exception e) { main.post(() -> done.accept(new ArrayList<>())); return; }
        main.postDelayed(() -> {
            try { nsd.stopServiceDiscovery(listener); } catch (Exception ignored) {}
            resolveNext(nsd, new ArrayDeque<>(found.values()), new ArrayList<>(), done);
        }, 3500);
    }
    @SuppressWarnings("deprecation")
    void resolveNext(NsdManager nsd, Deque<NsdServiceInfo> queue, List<Target> resolved, Consumer<List<Target>> done) {
        NsdServiceInfo next = queue.poll();
        if (next == null) { done.accept(resolved); return; }
        nsd.resolveService(next, new NsdManager.ResolveListener() {
            public void onResolveFailed(NsdServiceInfo info, int error) { main.post(() -> resolveNext(nsd, queue, resolved, done)); }
            public void onServiceResolved(NsdServiceInfo info) {
                InetAddress host = null;
                for (InetAddress a : info.getHostAddresses()) if (a instanceof Inet4Address && LinkClient.isLocal(a)) { host = a; break; }
                if (host == null) for (InetAddress a : info.getHostAddresses()) if (LinkClient.isLocal(a)) { host = a; break; }
                if (host != null) resolved.add(new Target(info.getServiceName(), host, info.getPort()));
                main.post(() -> resolveNext(nsd, queue, resolved, done));
            }
        });
    }
    /** The paired Mac, or the only one found; null when it's ambiguous or absent. */
    Target preferred(List<Target> list) {
        String saved = prefs.getString("service", null);
        for (Target t : list) if (t.name.equals(saved)) return t;
        return list.size() == 1 ? list.get(0) : null;
    }

    // MARK: Sending
    static byte[] bytes(JSONObject json) { return json.toString().getBytes(StandardCharsets.UTF_8); }
    static JSONObject envelope(String kind) throws JSONException {
        return new JSONObject().put("id", UUID.randomUUID().toString()).put("sentAt", System.currentTimeMillis() / 1000.0).put("kind", kind);
    }
    static String error(LinkClient.Response r) {
        try { return new JSONObject(r.text()).getString("error"); } catch (Exception e) { return "Your Mac replied with an error (" + r.status + ")."; }
    }
    static byte[] readAll(File file) throws IOException { try (InputStream in = new FileInputStream(file)) { return in.readAllBytes(); } }
    static JSONObject readJSON(File file) throws Exception { return new JSONObject(new String(readAll(file), StandardCharsets.UTF_8)); }

    private boolean heard;
    JSONObject send(Target target, String path, JSONObject envelope) throws Exception {
        byte[] key = key();
        LinkClient.Response r = LinkClient.post(target.host, target.port, path, Collections.singletonMap("X-Ascend-Phone", phoneID()), LinkCrypto.seal(bytes(envelope), key), 30000);
        if (r.status != 200) throw new LinkError(error(r));
        JSONObject reply = new JSONObject(new String(LinkCrypto.open(r.body, key), StandardCharsets.UTF_8));
        // Every reply carries the Mac's urge counts, upcoming doses and today's summary; keep the latest.
        SharedPreferences.Editor edit = prefs.edit();
        if (reply.has("urges")) { edit.putString("urgeCounts", reply.getJSONObject("urges").toString()); heard = true; }
        if (reply.has("today")) edit.putString("today", reply.getJSONObject("today").toString()).putLong("todayAt", System.currentTimeMillis());
        if (reply.has("meds")) edit.putString("medSchedule", reply.getJSONArray("meds").toString());
        edit.apply();
        if (reply.has("meds")) ReminderReceiver.schedule(context);
        return reply;
    }
    /**
     * Sends the health snapshot (if any), then queued meals, urges, medicine photos and doses. Each item is deleted
     * here only after the Mac accepts it. Blocking: call off the main thread. Returns a short summary.
     */
    String sendAll(Target target, JSONObject snapshot, String prefix) {
        StringBuilder summary = new StringBuilder(prefix);
        boolean ok = false;
        heard = false;
        try {
            if (snapshot != null) summary.append(send(target, "/v1/sync", envelope("sync").put("snapshot", snapshot)).optString("message")).append('\n');
            int meals = 0;
            for (File meta : queuedMeals()) {
                JSONObject m = readJSON(meta);
                File photo = new File(mealsDir(), m.getString("id") + ".jpg");
                if (!photo.exists()) { meta.delete(); continue; }
                JSONObject meal = new JSONObject().put("id", m.getString("id")).put("takenAt", m.getLong("takenAt")).put("note", m.optString("note"))
                    .put("mediaType", "image/jpeg").put("image", Base64.getEncoder().encodeToString(readAll(photo)));
                JSONObject reply = send(target, "/v1/meal", envelope("meal").put("meal", meal));
                if (reply.optBoolean("ok")) { photo.delete(); meta.delete(); meals++; }
                else summary.append(reply.optString("message", "A meal photo was rejected.")).append('\n');
            }
            if (meals > 0) summary.append(meals == 1 ? "1 meal photo sent.\n" : meals + " meal photos sent.\n");
            int urges = 0;
            for (File file : queuedUrges()) {
                JSONObject reply = send(target, "/v1/urge", envelope("urge").put("urge", readJSON(file)));
                if (reply.optBoolean("ok")) { file.delete(); urges++; }
                else summary.append(reply.optString("message", "An urge log was rejected.")).append('\n');
            }
            if (urges > 0) summary.append(urges == 1 ? "Urge logged on your Mac.\n" : urges + " urges logged on your Mac.\n");
            int medPhotos = 0;
            for (File batch : readyMedBatches()) {
                int size = readJSON(new File(batch, "ready.json")).getInt("size");
                for (File meta : json(batch)) {
                    JSONObject m = readJSON(meta);
                    File photo = new File(batch, m.getString("id") + ".jpg");
                    if (!photo.exists()) { meta.delete(); continue; }
                    JSONObject med = new JSONObject().put("id", m.getString("id")).put("batch", batch.getName()).put("batchSize", size).put("takenAt", m.getLong("takenAt"))
                        .put("mediaType", "image/jpeg").put("image", Base64.getEncoder().encodeToString(readAll(photo)));
                    JSONObject reply = send(target, "/v1/medphoto", envelope("medphoto").put("medPhoto", med));
                    if (reply.optBoolean("ok")) { photo.delete(); meta.delete(); medPhotos++; }
                    else summary.append(reply.optString("message", "A medicine photo was rejected.")).append('\n');
                }
                if (json(batch).length == 0) { new File(batch, "ready.json").delete(); batch.delete(); }
            }
            if (medPhotos > 0) summary.append(medPhotos == 1 ? "1 medicine photo sent; Claude is sorting it.\n" : medPhotos + " medicine photos sent; Claude is sorting them.\n");
            int doses = 0;
            for (File file : ReminderReceiver.queuedDoses(context)) {
                JSONObject reply = send(target, "/v1/dose", envelope("dose").put("dose", readJSON(file)));
                // A rejected dose (for example, the schedule changed) is dropped rather than retried forever.
                file.delete();
                if (reply.optBoolean("ok")) doses++; else summary.append(reply.optString("message", "A dose was rejected.")).append('\n');
            }
            if (doses > 0) summary.append(doses == 1 ? "Dose saved on your Mac.\n" : doses + " doses saved on your Mac.\n");
            int checkIns = 0;
            for (File file : queuedCheckIns()) {
                JSONObject reply = send(target, "/v1/checkin", envelope("checkin").put("checkIn", readJSON(file)));
                // Like doses, a check-in the Mac refuses (say, the habit changed) is dropped; the reply's Today shows the truth.
                file.delete();
                if (reply.optBoolean("ok")) checkIns++; else summary.append(reply.optString("message", "A check-in was rejected.")).append('\n');
            }
            if (checkIns > 0) summary.append(checkIns == 1 ? "Check-in saved on your Mac.\n" : checkIns + " check-ins saved on your Mac.\n");
            // Any reply carries the Mac's counts, doses and today; ask once if nothing was sent.
            if (!heard) { try { send(target, "/v1/hello", envelope("hello")); } catch (Exception ignored) {} }
            if (summary.length() == prefix.length()) summary.append("Up to date with your Mac.");
            ok = true;
        } catch (LinkError e) {
            summary.append(e.getMessage());
        } catch (Exception e) {
            summary.append("Couldn’t reach your Mac. Keep Ascend open on the Mac and both devices on the same Wi-Fi, then try again.");
        }
        String result = summary.toString().trim();
        SharedPreferences.Editor edit = prefs.edit().putString("lastSyncMessage", result);
        if (ok) edit.putLong("lastSync", System.currentTimeMillis());
        edit.apply();
        return result;
    }

    // MARK: Photos
    /** Downscales to 1568 px, turns the photo upright and re-encodes it as JPEG, which drops EXIF and location data. */
    static void writeUpright(Source source, File target) throws Exception {
        BitmapFactory.Options bounds = new BitmapFactory.Options(); bounds.inJustDecodeBounds = true;
        try (InputStream in = source.open()) { BitmapFactory.decodeStream(in, null, bounds); }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw new IOException("Not an image");
        int sample = 1;
        while (Math.max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_EDGE) sample *= 2;
        BitmapFactory.Options options = new BitmapFactory.Options(); options.inSampleSize = sample;
        Bitmap bitmap;
        try (InputStream in = source.open()) { bitmap = BitmapFactory.decodeStream(in, null, options); }
        if (bitmap == null) throw new IOException("Not an image");
        int orientation = ExifInterface.ORIENTATION_NORMAL;
        try (InputStream in = source.open()) { orientation = new ExifInterface(in).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL); } catch (Exception ignored) {}
        Matrix matrix = new Matrix();
        float scale = Math.min(1f, (float) MAX_EDGE / Math.max(bitmap.getWidth(), bitmap.getHeight()));
        matrix.postScale(scale, scale);
        if (orientation == ExifInterface.ORIENTATION_ROTATE_90) matrix.postRotate(90);
        else if (orientation == ExifInterface.ORIENTATION_ROTATE_180) matrix.postRotate(180);
        else if (orientation == ExifInterface.ORIENTATION_ROTATE_270) matrix.postRotate(270);
        Bitmap upright = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
        try (FileOutputStream out = new FileOutputStream(target)) { upright.compress(Bitmap.CompressFormat.JPEG, 85, out); }
    }

    // MARK: Health Connect (read-only)
    private Gate gate;
    private HealthDone callback;
    private JSONObject result, permissions, errors;
    private JSONArray records;
    private Instant start, end;
    private int typeIndex, stepSourceRecordCount, stepAggregateDays;

    /** Reads the last 14 days of every allowed type. `gate` is checked between steps so a locked screen stops a foreground read. */
    void readHealth(Gate gate, HealthDone done) {
        this.gate = gate; callback = done;
        typeIndex = 0; records = new JSONArray(); permissions = new JSONObject(); errors = new JSONObject(); result = new JSONObject();
        stepSourceRecordCount = 0; stepAggregateDays = 0;
        ZoneId zone = ZoneId.systemDefault();
        end = Instant.now(); start = LocalDate.now(zone).minusDays(13).atStartOfDay(zone).toInstant();
        try {
            result.put("version", 1).put("requestID", UUID.randomUUID().toString()).put("generatedAt", end.getEpochSecond()).put("rangeStart", start.getEpochSecond())
                .put("rangeEnd", end.getEpochSecond()).put("sourcePackage", SOURCE).put("permissions", permissions).put("errors", errors).put("records", records);
            for (int i = 0; i < KEYS.length; i++) permissions.put(KEYS[i], allowed(i));
        } catch (JSONException e) { fail("Could not start the health export."); return; }
        next();
    }
    private void fail(String message) { HealthDone done = callback; callback = null; if (done != null) done.done(null, message); }
    private void next() {
        if (!gate.open()) { fail("Health data paused because the phone locked or the app closed. Open it again to sync."); return; }
        if (typeIndex >= KEYS.length) { finish(); return; }
        int i = typeIndex;
        if (!allowed(i)) { typeIndex++; next(); return; }
        if (i == 1) inspectStepsSource(-1, 0); else read(i, -1, 0);
    }
    private void finish() {
        if (result.toString().length() > 11_000_000) { fail("Health export is too large to send. No health data was sent."); return; }
        HealthDone done = callback; callback = null;
        if (done != null) done.done(result, null);
    }
    // Diagnose the source handoff without adding raw intervals to daily aggregates.
    // Never sum both representations or silently broaden the source to phone/other apps.
    private void inspectStepsSource(long token, int pages) {
        if (!gate.open()) { fail("Health data paused because the phone locked or the app closed. Open it again to sync."); return; }
        if (pages >= 80) { fail("Steps diagnostics exceeded the local safety limit. No health data was sent."); return; }
        ReadRecordsRequestUsingFilters.Builder<StepsRecord> builder = new ReadRecordsRequestUsingFilters.Builder<>(StepsRecord.class);
        builder.addDataOrigins(new DataOrigin.Builder().setPackageName(SOURCE).build());
        builder.setTimeRangeFilter(new TimeInstantRangeFilter.Builder().setStartTime(start).setEndTime(end).build());
        builder.setPageSize(1000); if (token != -1) builder.setPageToken(token);
        try {
            manager.readRecords(builder.build(), context.getMainExecutor(), new OutcomeReceiver<ReadRecordsResponse<StepsRecord>, HealthConnectException>() {
                public void onResult(ReadRecordsResponse<StepsRecord> response) {
                    for (StepsRecord record : response.getRecords()) {
                        if (!SOURCE.equals(record.getMetadata().getDataOrigin().getPackageName())) { fail("Unexpected steps source. No health data was sent."); return; }
                        stepSourceRecordCount++;
                    }
                    long next = response.getNextPageToken();
                    if (next != -1) inspectStepsSource(next, pages + 1); else readStepsDay(0);
                }
                public void onError(HealthConnectException e) { stepsError("Steps source check failed. Retry the sync."); }
            });
        } catch (Exception e) { stepsError("Steps source check unavailable. Review Health Connect permissions."); }
    }
    private void stepsError(String message) { try { errors.put("steps", message); } catch (Exception ignored) {} typeIndex++; next(); }
    private void readStepsDay(int day) {
        if (!gate.open()) { fail("Health data paused because the phone locked or the app closed. Open it again to sync."); return; }
        if (day == 14) {
            try {
                result.put("diagnostics", new JSONObject().put("steps", new JSONObject().put("sourceRecordCount", stepSourceRecordCount).put("aggregateDays", stepAggregateDays)));
                if (stepSourceRecordCount > 0 && stepAggregateDays == 0) errors.put("steps", "Mi Fitness has step entries, but Health Connect returned no daily totals. Review Health Connect activity sources, then retry. Earlier steps are retained.");
            } catch (JSONException e) { fail("Could not encode steps diagnostics."); return; }
            typeIndex++; next(); return;
        }
        Instant a = start.plus(Duration.ofDays(day)); Instant b = a.plus(Duration.ofDays(1)); if (b.isAfter(end)) b = end;
        final Instant stop = b;
        AggregateRecordsRequest<Long> request = new AggregateRecordsRequest.Builder<Long>(new TimeInstantRangeFilter.Builder().setStartTime(a).setEndTime(b).build())
            .addAggregationType(StepsRecord.STEPS_COUNT_TOTAL).addDataOriginsFilter(new DataOrigin.Builder().setPackageName(SOURCE).build()).build();
        try {
            manager.aggregate(request, context.getMainExecutor(), new OutcomeReceiver<AggregateRecordsResponse<Long>, HealthConnectException>() {
                public void onResult(AggregateRecordsResponse<Long> response) {
                    try {
                        Long count = response.get(StepsRecord.STEPS_COUNT_TOTAL);
                        if (count != null) { stepAggregateDays++; records.put(new JSONObject().put("id", "steps-day-" + a.getEpochSecond()).put("metric", "steps").put("start", a.getEpochSecond()).put("end", stop.getEpochSecond()).put("value", count).put("detail", "Health Connect daily aggregate").put("device", "")); }
                    } catch (Exception e) { fail("Could not encode daily steps."); return; }
                    readStepsDay(day + 1);
                }
                public void onError(HealthConnectException e) { try { errors.put("steps", "Daily steps unavailable. Retry the sync."); } catch (Exception ignored) {} typeIndex++; next(); }
            });
        } catch (Exception e) { try { errors.put("steps", "Steps access unavailable."); } catch (Exception ignored) {} typeIndex++; next(); }
    }
    @SuppressWarnings({"unchecked", "rawtypes"}) private void read(int index, long token, int pages) {
        if (pages >= 80 || records.length() >= 100000) { fail("Health export exceeds the local safety limit. No health data was sent."); return; }
        ReadRecordsRequestUsingFilters.Builder builder = new ReadRecordsRequestUsingFilters.Builder(TYPES[index]);
        builder.addDataOrigins(new DataOrigin.Builder().setPackageName(SOURCE).build());
        builder.setTimeRangeFilter(new TimeInstantRangeFilter.Builder().setStartTime(start).setEndTime(end).build());
        builder.setPageSize(1000);
        if (token != -1) builder.setPageToken(token);
        try {
            manager.readRecords(builder.build(), context.getMainExecutor(), new OutcomeReceiver<ReadRecordsResponse<Record>, HealthConnectException>() {
                public void onResult(ReadRecordsResponse<Record> response) {
                    try { for (Record r : response.getRecords()) addRecord(r, index); }
                    catch (Exception e) { fail("Could not encode health records. No health data was sent."); return; }
                    long next = response.getNextPageToken();
                    if (next != -1) read(index, next, pages + 1); else { typeIndex++; next(); }
                }
                public void onError(HealthConnectException e) {
                    try { errors.put(KEYS[index], "Health Connect error " + e.getErrorCode() + ". Retry the sync."); } catch (Exception ignored) {}
                    typeIndex++; next();
                }
            });
        } catch (Exception e) {
            try { errors.put(KEYS[index], "Access unavailable. Review permissions in Health Connect."); } catch (Exception ignored) {}
            typeIndex++; next();
        }
    }
    private JSONObject base(Record r, int type, Instant a, Instant b, String suffix, double value, String detail) throws JSONException {
        String model = "";
        if (r.getMetadata().getDevice() != null) model = r.getMetadata().getDevice().getModel();
        return new JSONObject().put("id", r.getMetadata().getId() + suffix).put("metric", KEYS[type]).put("start", a.getEpochSecond()).put("end", b.getEpochSecond())
            .put("value", value).put("detail", detail).put("device", model == null ? "" : model);
    }
    /** Names match SleepStageKind on the Mac; anything unexpected is sent as "unknown". */
    static String stageKind(int type) {
        switch (type) {
            case SleepSessionRecord.StageType.STAGE_TYPE_AWAKE: return "awake";
            case SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING: return "asleep";
            case SleepSessionRecord.StageType.STAGE_TYPE_AWAKE_OUT_OF_BED: return "outOfBed";
            case SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING_LIGHT: return "light";
            case SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING_DEEP: return "deep";
            case SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING_REM: return "rem";
            case SleepSessionRecord.StageType.STAGE_TYPE_AWAKE_IN_BED: return "awakeInBed";
            default: return "unknown";
        }
    }
    private void addRecord(Record r, int i) throws JSONException {
        if (!SOURCE.equals(r.getMetadata().getDataOrigin().getPackageName())) throw new IllegalStateException("Unexpected source");
        // Mi Fitness writes some totals (activity calories) as one record for the whole day,
        // so today's record ends after this sync. Send its value so far with the end capped
        // at the sync time and marked in progress; the stable ID replaces it next sync.
        // A sleep session still in progress is left for a later sync.
        boolean inProgress = false;
        if (r instanceof IntervalRecord && !(r instanceof HeartRateRecord) && !(r instanceof SpeedRecord)) {
            if (((IntervalRecord) r).getEndTime().isAfter(end)) {
                if (r instanceof SleepSessionRecord) return;
                inProgress = true;
            }
        }
        if (r instanceof HeartRateRecord) {
            HeartRateRecord x = (HeartRateRecord) r; int n = 0;
            for (HeartRateRecord.HeartRateSample s : x.getSamples()) { int sample = n++; if (!s.getTime().isBefore(start) && !s.getTime().isAfter(end)) records.put(base(r, i, s.getTime(), s.getTime(), ":" + sample, s.getBeatsPerMinute(), "")); }
        } else if (r instanceof SpeedRecord) {
            SpeedRecord x = (SpeedRecord) r; int n = 0;
            for (SpeedRecord.SpeedRecordSample s : x.getSamples()) { int sample = n++; if (!s.getTime().isBefore(start) && !s.getTime().isAfter(end)) records.put(base(r, i, s.getTime(), s.getTime(), ":" + sample, s.getSpeed().getInMetersPerSecond(), "")); }
        } else if (r instanceof OxygenSaturationRecord) {
            OxygenSaturationRecord x = (OxygenSaturationRecord) r; records.put(base(r, i, x.getTime(), x.getTime(), "", x.getPercentage().getValue(), ""));
        } else if (r instanceof IntervalRecord) {
            IntervalRecord x = (IntervalRecord) r; double value = 0; String detail = ""; JSONArray stages = null;
            if (r instanceof StepsRecord) value = ((StepsRecord) r).getCount();
            else if (r instanceof DistanceRecord) value = ((DistanceRecord) r).getDistance().getInMeters();
            else if (r instanceof ActiveCaloriesBurnedRecord) value = ((ActiveCaloriesBurnedRecord) r).getEnergy().getInCalories() / 1000.0;
            else if (r instanceof ElevationGainedRecord) value = ((ElevationGainedRecord) r).getElevation().getInMeters();
            else if (r instanceof ExerciseSessionRecord) { value = Duration.between(x.getStartTime(), inProgress ? end : x.getEndTime()).getSeconds() / 60.0; detail = "Exercise type " + ((ExerciseSessionRecord) r).getExerciseType(); }
            else if (r instanceof SleepSessionRecord) {
                SleepSessionRecord sleep = (SleepSessionRecord) r; long seconds = 0;
                for (SleepSessionRecord.Stage s : sleep.getStages()) { int t = s.getType(); if (t == SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING || t == SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING_LIGHT || t == SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING_DEEP || t == SleepSessionRecord.StageType.STAGE_TYPE_SLEEPING_REM) seconds += Duration.between(s.getStartTime(), s.getEndTime()).getSeconds(); }
                boolean staged = seconds > 0; value = (staged ? seconds : Duration.between(x.getStartTime(), x.getEndTime()).getSeconds()) / 3600.0; detail = staged ? "Asleep stages" : "Session window";
                // Stage intervals for the cycle chart, capped to keep the export bounded.
                stages = new JSONArray();
                for (SleepSessionRecord.Stage s : sleep.getStages()) {
                    if (stages.length() >= 1000) break;
                    stages.put(new JSONObject().put("start", s.getStartTime().getEpochSecond()).put("end", s.getEndTime().getEpochSecond()).put("kind", stageKind(s.getType())));
                }
            }
            JSONObject record = base(r, i, x.getStartTime(), inProgress ? end : x.getEndTime(), "", value, inProgress ? "In progress" : detail);
            if (stages != null && stages.length() > 0) record.put("stages", stages);
            records.put(record);
        }
        if (records.length() > 100000) throw new IllegalStateException("Too many records");
    }
}
