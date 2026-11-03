package com.abdul.ascend.bridge;

import java.time.*;
import java.util.*;

/** Event-only math, independent of Android. No app content or activity names leave the collector. */
final class ScreenTimeMath {
    static final int ON=1, OFF=2, RESUME=3, PAUSE=4, SHUTDOWN=5, STARTUP=6;
    record Event(long at, int kind, String pkg, String activity) {}
    record Interval(long start, long end) {}
    static final class Day {
        long start, end, screenMillis;
        boolean complete = true;
        final Map<String,Long> apps = new HashMap<>();
        final Map<Long,Long> hours = new TreeMap<>();
        Day(long start, long end) { this.start=start; this.end=end; }
    }
    static List<Day> calculate(List<Event> events, ZoneId zone, long start, long end, boolean interactiveNow) {
        List<Day> days = new ArrayList<>();
        for (ZonedDateTime d=Instant.ofEpochMilli(start).atZone(zone); d.toInstant().toEpochMilli()<end; d=d.plusDays(1))
            days.add(new Day(d.toInstant().toEpochMilli(), Math.min(end,d.plusDays(1).toInstant().toEpochMilli())));
        List<Interval> screen = new ArrayList<>(), unknown = new ArrayList<>();
        Map<String,List<Interval>> appIntervals = new HashMap<>();
        Map<String,Set<String>> active = new HashMap<>();
        Map<String,Long> appStart = new HashMap<>();
        Long on = null;
        boolean known = false;
        long unknownStart = start, offAt = start;
        for (Event e:events) {
            if (e.at>end) break;
            switch (e.kind) {
            case ON:
                if (!known) unknown.add(new Interval(unknownStart,e.at));
                known=true;
                if (on==null) on=e.at;
                break;
            case OFF:
                if (!known) unknown.add(new Interval(unknownStart,e.at));
                if (on!=null) screen.add(new Interval(on,e.at));
                on=null; known=true;offAt=e.at;
                closeApps(appStart,appIntervals,e.at); active.clear();
                break;
            case RESUME:
                if (e.pkg==null || e.pkg.isEmpty()) break;
                Set<String> classes=active.computeIfAbsent(e.pkg,k->new HashSet<>());
                if (classes.isEmpty()) appStart.put(e.pkg,e.at);
                classes.add(e.activity==null?"":e.activity);
                break;
            case PAUSE:
                Set<String> existing=active.get(e.pkg);
                if (existing!=null) {
                    existing.remove(e.activity==null?"":e.activity);
                    if (existing.isEmpty()) {
                        Long a=appStart.remove(e.pkg);
                        if (a!=null) appIntervals.computeIfAbsent(e.pkg,k->new ArrayList<>()).add(new Interval(a,e.at));
                    }
                }
                break;
            case SHUTDOWN: case STARTUP:
                // Android documents unmatched sessions across a restart as having unknown closing times.
                if (on!=null) unknown.add(new Interval(on,e.at));
                if (!known) unknown.add(new Interval(unknownStart,e.at));
                on=null; known=false; unknownStart=e.at; appStart.clear(); active.clear();
                break;
            default: break;
            }
        }
        if (!known) unknown.add(new Interval(unknownStart,end));
        if (known && on==null && interactiveNow) unknown.add(new Interval(offAt,end));
        if (on!=null) {
            if (interactiveNow) { screen.add(new Interval(on,end)); closeApps(appStart,appIntervals,end); }
            else unknown.add(new Interval(on,end));
        }
        for (Day day:days) {
            for (Interval x:unknown) if (Math.min(x.end,day.end)>Math.max(x.start,day.start)) day.complete=false;
            for (Interval x:screen) {
                long a=Math.max(day.start,x.start), b=Math.min(day.end,x.end);
                if (b<=a) continue;
                day.screenMillis+=b-a;
                for (long t=a;t<b;) {
                    long hour=Instant.ofEpochMilli(t).atZone(zone).withMinute(0).withSecond(0).withNano(0).toInstant().toEpochMilli();
                    long stop=Math.min(b,hour+3600000);
                    day.hours.merge(hour,stop-t,Long::sum);t=stop;
                }
            }
            for (var entry:appIntervals.entrySet()) {
                long total=0;
                List<Interval> aa=entry.getValue();int i=0,j=0;
                while (i<aa.size() && j<screen.size()) {
                    Interval app=aa.get(i), s=screen.get(j);
                    long a=Math.max(day.start,Math.max(app.start,s.start)), b=Math.min(day.end,Math.min(app.end,s.end));
                    if (b>a) total+=b-a;
                    if (app.end<=s.end) i++; else j++;
                }
                if (total>0) day.apps.put(entry.getKey(),total);
            }
        }
        return days;
    }
    private static void closeApps(Map<String,Long> starts,Map<String,List<Interval>> intervals,long end) {
        for (var entry:starts.entrySet()) if (end>entry.getValue()) intervals.computeIfAbsent(entry.getKey(),k->new ArrayList<>()).add(new Interval(entry.getValue(),end));
        starts.clear();
    }
}
