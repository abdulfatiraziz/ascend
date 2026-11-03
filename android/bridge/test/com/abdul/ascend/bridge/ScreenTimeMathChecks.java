package com.abdul.ascend.bridge;
import java.time.*;
import java.util.*;

public final class ScreenTimeMathChecks {
    static int count;
    static ScreenTimeMath.Event e(long at,int kind,String pkg,String activity) { return new ScreenTimeMath.Event(at,kind,pkg,activity); }
    static void check(boolean value,String name) { if(!value)throw new AssertionError(name);System.out.println("PASS: "+name);count++; }
    static List<ScreenTimeMath.Day> calc(List<ScreenTimeMath.Event> events,long start,long end,boolean on) { return ScreenTimeMath.calculate(events,ZoneId.of("UTC"),start,end,on); }
    public static void main(String[] args) {
        var d=calc(List.of(e(-1,2,"",""),e(1000,1,"",""),e(2000,3,"a","A"),e(32000,4,"a","A"),e(61000,2,"","")),0,62000,false).get(0);
        check(d.screenMillis==60000 && d.apps.get("a")==30000 && d.complete,"screen-on and app foreground durations are distinct");
        d=calc(List.of(e(0,1,"",""),e(2000,3,"a","A"),e(3000,3,"a","B"),e(4000,4,"a","A"),e(6000,4,"a","B"),e(10000,2,"","")),0,11000,false).get(0);
        check(d.apps.get("a")==4000,"overlapping activities in one app do not double count");
        d=calc(List.of(e(0,1,"",""),e(2000,3,"a","A"),e(3000,3,"b","B"),e(8000,4,"a","A"),e(9000,4,"b","B"),e(10000,2,"","")),0,11000,false).get(0);
        check(d.screenMillis==10000 && d.apps.values().stream().mapToLong(Long::longValue).sum()==12000,"split-screen apps may overlap without inflating device time");
        var days=calc(List.of(e(-1,2,"",""),e(85800000,1,"",""),e(87000000,2,"","")),0,87300000,false);
        check(days.size()==2 && days.get(0).screenMillis==600000 && days.get(1).screenMillis==600000,"sessions crossing midnight split into local days");
        ZoneId zone=ZoneId.of("Europe/Berlin");
        for(String date:List.of("2026-03-29","2026-10-25")) {
            ZonedDateTime begin=LocalDate.parse(date).atStartOfDay(zone);long a=begin.toInstant().toEpochMilli(),b=begin.plusDays(1).toInstant().toEpochMilli();
            var day=ScreenTimeMath.calculate(List.of(e(a,1,"",""),e(b,2,"","")),zone,a,b,false).get(0);
            check(day.screenMillis==b-a && day.hours.size()==(b-a)/3600000 && day.hours.values().stream().mapToLong(Long::longValue).sum()==b-a,"DST day and hourly buckets: "+date);
        }
        d=calc(List.of(e(1000,1,"",""),e(5000,2,"","")),0,6000,false).get(0);
        check(!d.complete && d.screenMillis==4000,"missing prefix is partial, not fabricated zero");
        d=calc(List.of(e(0,1,"",""),e(5000,5,"",""),e(6000,6,"",""),e(7000,2,"","")),0,8000,false).get(0);
        check(!d.complete && d.screenMillis==0,"unmatched screen sessions across restart are discarded");
        var events=List.of(e(0,1,"",""),e(1000,3,"a","A"));
        d=calc(events,0,5000,true).get(0);
        check(d.screenMillis==5000 && d.apps.get("a")==4000,"known ongoing interactive session is clipped to snapshot time");
        d=calc(events,0,5000,false).get(0);
        check(!d.complete && d.screenMillis==0,"contradictory current screen state does not invent an endpoint");
        d=calc(List.of(e(0,2,"","")),0,5000,false).get(0);
        check(d.complete && d.screenMillis==0,"known screen-off interval can represent real zero");
        System.out.println(count+" screen-time math checks, 0 failures");
    }
}
