package com.abdul.ascend.bridge;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Hourly background sync on Wi-Fi. It looks for the paired Mac first and reads health data only when the Mac is
 * there, so nothing happens away from home. Needs Health Connect's "read in background" permission.
 */
public final class SyncJob extends JobService {
    static final int ID = 4201;
    private final ExecutorService network = Executors.newSingleThreadExecutor();

    /**
     * Turns the hourly job on or off. Safe to call repeatedly; an existing job keeps its schedule.
     * Returns false when Android refuses the job, so a scheduling problem never crashes the app.
     */
    static boolean schedule(Context context, boolean on) {
        JobScheduler jobs = context.getSystemService(JobScheduler.class);
        try {
            if (!on) { jobs.cancel(ID); return true; }
            if (jobs.getPendingJob(ID) != null) return true;
            return jobs.schedule(new JobInfo.Builder(ID, new ComponentName(context, SyncJob.class))
                .setPeriodic(60 * 60 * 1000L, 20 * 60 * 1000L)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_UNMETERED)
                .setPersisted(true).build()) == JobScheduler.RESULT_SUCCESS;
        } catch (RuntimeException e) {
            context.getSharedPreferences("link", MODE_PRIVATE).edit().putBoolean("backgroundSync", false).apply();
            return false;
        }
    }
    static boolean enabled(Context context) {
        return context.getSharedPreferences("link", MODE_PRIVATE).getBoolean("backgroundSync", false);
    }

    @Override public boolean onStartJob(JobParameters params) {
        SyncEngine engine = new SyncEngine(this);
        if (!enabled(this) || !engine.paired() || !engine.backgroundAllowed() || !SyncEngine.RUNNING.compareAndSet(false, true)) return false;
        engine.discover(list -> {
            SyncEngine.Target target = engine.preferred(list);
            if (target == null) { done(params); return; }
            engine.readHealth(() -> true, (snapshot, problem) ->
                network.execute(() -> { engine.sendAll(target, snapshot, problem == null ? "" : problem + "\n"); done(params); }));
        });
        return true;
    }
    private void done(JobParameters params) { SyncEngine.RUNNING.set(false); jobFinished(params, false); }
    @Override public boolean onStopJob(JobParameters params) { SyncEngine.RUNNING.set(false); return true; }
    @Override public void onDestroy() { super.onDestroy(); network.shutdown(); }
}
