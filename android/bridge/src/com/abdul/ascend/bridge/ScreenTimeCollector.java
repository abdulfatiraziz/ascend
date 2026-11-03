package com.abdul.ascend.bridge;

import android.app.AppOpsManager;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.PowerManager;
import android.os.Process;
import android.os.UserManager;
import org.json.*;
import java.time.*;
import java.util.*;

final class ScreenTimeCollector {
    static boolean allowed(Context c) {
        return c.getSystemService(AppOpsManager.class).unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,Process.myUid(),c.getPackageName())==AppOpsManager.MODE_ALLOWED;
    }
    static boolean sharing(Context c) { return c.getSharedPreferences("link",Context.MODE_PRIVATE).getBoolean("screenTimeSharing",false); }
    static JSONObject snapshot(Context c) throws Exception {
        long now=System.currentTimeMillis();
        ZoneId zone=ZoneId.systemDefault();
        JSONObject result=new JSONObject().put("version",1).put("generatedAt",now/1000.0).put("timeZoneID",zone.getId()).put("days",new JSONArray());
        if (!sharing(c)) return result.put("status","disabled");
        if (!allowed(c)) return result.put("status","denied");
        if (!c.getSystemService(UserManager.class).isUserUnlocked()) return result.put("status","unavailable");
        ZonedDateTime first=Instant.ofEpochMilli(now).atZone(zone).toLocalDate().minusDays(6).atStartOfDay(zone);
        UsageEvents source=c.getSystemService(UsageStatsManager.class).queryEvents(first.minusDays(1).toInstant().toEpochMilli(),now);
        if (source==null) return result.put("status","unavailable");
        List<ScreenTimeMath.Event> events=new ArrayList<>();UsageEvents.Event e=new UsageEvents.Event();int count=0;
        while (source.hasNextEvent()) {
            source.getNextEvent(e);
            if (++count>200000) return result.put("status","unavailable");
            int kind=switch(e.getEventType()) {
                case UsageEvents.Event.SCREEN_INTERACTIVE -> ScreenTimeMath.ON;
                case UsageEvents.Event.SCREEN_NON_INTERACTIVE -> ScreenTimeMath.OFF;
                case UsageEvents.Event.ACTIVITY_RESUMED -> ScreenTimeMath.RESUME;
                case UsageEvents.Event.ACTIVITY_PAUSED,UsageEvents.Event.ACTIVITY_STOPPED -> ScreenTimeMath.PAUSE;
                case UsageEvents.Event.DEVICE_SHUTDOWN -> ScreenTimeMath.SHUTDOWN;
                case UsageEvents.Event.DEVICE_STARTUP -> ScreenTimeMath.STARTUP;
                default -> 0;
            };
            if (kind!=0) events.add(new ScreenTimeMath.Event(e.getTimeStamp(),kind,e.getPackageName(),e.getClassName()));
        }
        if (events.isEmpty()) return result.put("status","unavailable");
        events.sort(Comparator.comparingLong(ScreenTimeMath.Event::at));
        List<ScreenTimeMath.Day> days=ScreenTimeMath.calculate(events,zone,first.toInstant().toEpochMilli(),now,c.getSystemService(PowerManager.class).isInteractive());
        JSONArray output=new JSONArray();
        for (var day:days) {
            JSONArray apps=new JSONArray(),hours=new JSONArray();
            if (day.apps.size()>1000) return result.put("status","unavailable");
            for (var entry:day.apps.entrySet()) {
                String label=entry.getKey();
                try { var info=c.getPackageManager().getApplicationInfo(entry.getKey(),0);label=c.getPackageManager().getApplicationLabel(info).toString(); } catch (PackageManager.NameNotFoundException|SecurityException ignored) {}
                if (label.length()>200) label=label.substring(0,200);
                apps.put(new JSONObject().put("packageName",entry.getKey()).put("label",label).put("seconds",entry.getValue()/1000.0));
            }
            for (var entry:day.hours.entrySet()) hours.put(new JSONObject().put("start",entry.getKey()/1000.0).put("seconds",entry.getValue()/1000.0));
            output.put(new JSONObject().put("start",day.start/1000.0).put("end",day.end/1000.0).put("complete",day.complete)
                .put("screenSeconds",!day.complete&&day.screenMillis==0?JSONObject.NULL:day.screenMillis/1000.0).put("apps",apps).put("hours",hours));
        }
        return result.put("status","allowed").put("days",output);
    }
}
