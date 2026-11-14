import AscendCore
import Foundation

func runDietChecks() -> (count:Int,failures:Int) {
    var count=0,failures=0
    struct Failure:Error {}
    func expect(_ value:Bool) throws {if !value{throw Failure()}}
    func rejects(_ body:() throws -> Void) throws {do{try body()}catch{return};throw Failure()}
    func check(_ name:String,_ body:() throws -> Void){count+=1;do{try body();print("PASS: \(name)")}catch{failures+=1;print("FAIL: \(name): \(error)")}}
    func fixture() -> TrackerDocument {
        TrackerDocument.seeded(today:"2026-06-01",timeZoneID:"UTC")
    }
    let limits=Dictionary(uniqueKeysWithValues:(1...7).map{($0,($0==1 || $0==7) ? 2250.0:1850.0)})
    func plan(_ doc:TrackerDocument) -> DietPlan {
        var p=DietPlan(effectiveDay:"2026-06-08")
        p.slots=[.init(name:"Breakfast",startMinute:540,endMinute:660,kcal:410,protein:24,cafeReplacement:true),.init(name:"Dessert",startMinute:1260,endMinute:1320,kcal:180,protein:16,sweet:true)]
        p.references=[.init(name:"rice",kcal:140,protein:3,carbs:29),.init(name:"oil",kcal:880,fat:98,tablespoonGrams:12,sprayGrams:0.4)]
        p.sweetsHabitID=doc.habits.first{$0.kind == .check}?.id
        return p
    }
    func meal(_ e:TrackerEngine,_ day:String,_ minute:Int,kind:MealDietKind = .standard,confirmed:Bool=true,kcal:Double=320) -> MealEntry {
        let at=e.calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:e.date(day)!)!
        var m=MealEntry(takenAt:at.timeIntervalSince1970,day:day,photo:"",source:"mac")
        m.dietKind=kind;m.confirmed=confirmed;m.kcal=kcal;m.protein=21;return m
    }
    check("Today: 'as planned' logs the plan slot due now with its calories and protein, then moves to the next slot") {
        var d=fixture();let e=TrackerEngine(document:d);d.diet=plan(d)
        let day="2026-06-08"
        try expect(d.suggestedPlanSlot(on:day,minute:600,engine:e)?.name=="Breakfast")
        try d.logPlanned(d.diet!.slots[0],day:day,now:e.calendar.date(bySettingHour:23,minute:0,second:0,of:e.date(day)!)!,engine:e,today:day)
        let m=d.meals.on(day)
        try expect(m.count==1 && m[0].kcal==410 && m[0].protein==24 && m[0].confirmed && m[0].dietKind == .cafe && m[0].photos.isEmpty)
        let slots=d.planSlots(on:day,engine:e)
        try expect(slots.map(\.logged)==[true,false])
        try expect(d.suggestedPlanSlot(on:day,minute:600,engine:e)?.name=="Dessert")
        try d.validate()
    }
    check("Today: habits that fill themselves are never listed as taps") {
        var d=fixture();d.diet=plan(d)
        let auto=d.autoHabitIDs
        if let s=d.sweetsHabit { try expect(auto.contains(s.id)) }
        if let c=d.mealHabits.calories { try expect(auto.contains(c.id)) }
        try expect(d.accentHabit.map { !auto.contains($0.id) } ?? true)
    }
    check("legacy tracker and habit revisions decode without diet fields") {
        let d=fixture(),data=try JSONEncoder().encode(d)
        let copy=try JSONDecoder().decode(TrackerDocument.self,from:data)
        try expect(copy.diet==nil && copy.habits.allSatisfy{$0.latest.weekdayTargets==nil});try copy.validate()
    }
    check("weekday targets revise today and preserve earlier scoring and habit IDs") {
        var d=fixture();let old=d.mealHabits.calories!,id=old.id
        d.setEntry(CheckIn(habitID:id,day:"2026-06-07",value:2100));d.setEntry(CheckIn(habitID:id,day:"2026-06-13",value:2100))
        let before=TrackerEngine(document:d).completed(old,on:"2026-06-07")
        try d.applyDietPlan(plan(d),weekdayLimits:limits,today:"2026-06-08")
        let h=d.mealHabits.calories!,e=TrackerEngine(document:d)
        try expect(h.id==id && e.completed(h,on:"2026-06-07")==before && e.completed(h,on:"2026-06-13"))
        try expect(e.target(for:h,on:"2026-06-08")?.maximum==1850 && e.target(for:h,on:"2026-06-14")?.maximum==2250)
    }
    check("phone checklist sends resolved weekday target") {
        var d=fixture();try d.applyDietPlan(plan(d),weekdayLimits:limits,today:"2026-06-08")
        let item=d.phoneHabits(today:"2026-06-13").first{$0.id==d.mealHabits.calories!.id.uuidString}
        try expect(item?.maximum==2250 && item?.target==TrackerEngine(document:d).target(for:d.mealHabits.calories!,on:"2026-06-13")?.label)
        try expect(d.phoneToday(today:"2026-06-13").kcalLimit==2250)
    }
    check("diet and weekday overrides survive JSON backup round trip") {
        var d=fixture();try d.applyDietPlan(plan(d),weekdayLimits:limits,today:"2026-06-08")
        let copy=try JSONDecoder().decode(TrackerDocument.self,from:JSONEncoder().encode(d));try copy.validate();try expect(copy==d)
    }
    check("invalid weekday maps reject units, bounds and weekday indices") {
        var d=fixture();let i=d.habits.firstIndex{$0.id==d.mealHabits.calories!.id}!,j=d.habits[i].revisions.count-1
        for targets in [[8:MetricTarget(maximum:1000,unit:"kcal")],[2:MetricTarget(maximum:1000,unit:"g")],[2:MetricTarget(minimum:2000,maximum:1000,unit:"kcal")],[2:MetricTarget(maximum:.infinity,unit:"kcal")]] {
            d.habits[i].revisions[j].weekdayTargets=targets;try rejects{try d.validate()}
        }
    }
    check("failed diet update is atomic and repeat setup does not add revisions") {
        var d=fixture();let original=d
        try rejects{try d.applyDietPlan(plan(d),weekdayLimits:[2:1800],today:"2026-06-08")};try expect(d==original)
        let p=plan(d);try d.applyDietPlan(p,weekdayLimits:limits,today:"2026-06-08");let once=d
        try d.applyDietPlan(p,weekdayLimits:limits,today:"2026-06-08");try expect(d==once)
    }
    check("weekly budget uses Monday week and avoids double-counting meal-filled check-ins") {
        var d=fixture();try d.applyDietPlan(plan(d),weekdayLimits:limits,today:"2026-06-08")
        let e=TrackerEngine(document:d);d.meals.entries=[meal(e,"2026-06-08",600),meal(e,"2026-06-09",600,confirmed:false,kcal:999)]
        d.applyMealTotals(on:"2026-06-08",today:"2026-06-14")
        d.setEntry(CheckIn(habitID:d.mealHabits.calories!.id,day:"2026-06-10",value:700))
        let b=DietBudget.build(document:d,day:"2026-06-14")!
        try expect(b.start=="2026-06-08" && b.planned==13750 && b.consumed==1020 && b.loggedDays==2 && b.targetDays==7)
    }
    check("meal slots count confirmed meals and café replacement only in its window") {
        let d=fixture(),e=TrackerEngine(document:d),p=plan(d)
        try expect(p.slot(for:meal(e,"2026-06-08",600,kind:.cafe),calendar:e.calendar)?.cafeReplacement==true)
        try expect(p.slot(for:meal(e,"2026-06-08",900,kind:.cafe),calendar:e.calendar)==nil)
    }
    check("sweet boundaries are half-open; unconfirmed or earlier-day sweets never block") {
        var d=fixture();let p=plan(d),e=TrackerEngine(document:d)
        d.meals.entries=[meal(e,"2026-06-08",1260,kind:.sweet),meal(e,"2026-06-08",1320,kind:.sweet),meal(e,"2026-06-08",1200,kind:.sweet,confirmed:false)]
        try expect(p.unplannedSweets(d.meals,day:"2026-06-08",calendar:e.calendar).count==1)
        try expect(p.unplannedSweets(d.meals,day:"2026-06-07",calendar:e.calendar).isEmpty)
    }
    check("outside sweet blocks linked check-in without overwriting manual completion") {
        var d=fixture();let p=plan(d);d.diet=p
        let h=d.habits.first{$0.id==p.sweetsHabitID}!,e=TrackerEngine(document:d)
        d.setEntry(CheckIn(habitID:h.id,day:"2026-06-08",completed:true))
        d.meals.entries=[meal(e,"2026-06-08",1100,kind:.sweet)]
        try expect(!TrackerEngine(document:d).completed(h,on:"2026-06-08"))
        d.meals.entries=[];try expect(TrackerEngine(document:d).completed(h,on:"2026-06-08"))
    }
    check("meal windows use tracker timezone across midnight") {
        var d=fixture();d.timeZoneID="Asia/Tokyo";let e=TrackerEngine(document:d),p=plan(d)
        let m=meal(e,"2026-06-08",1275,kind:.sweet)
        try expect(p.slot(for:m,calendar:e.calendar)?.sweet==true)
    }
    check("gram calculator supports grams, tablespoon and calibrated spray shorthand") {
        let refs=plan(fixture()).references
        let rice=try FoodCalculation.parse("rice 85 g",references:refs)
        let oil=try FoodCalculation.parse("+1 tbsp oil",references:refs)
        let spray=try FoodCalculation.parse("spray ×5",references:refs)
        try expect(abs(rice.totals.kcal-119)<0.001 && oil.grams==12 && spray.grams==2)
        var noCalibration=refs;noCalibration[1].sprayGrams=nil
        try rejects{_ = try FoodCalculation.parse("oil spray x5",references:noCalibration)}
        for text in ["rice -3 g","rice nan g","rice infinity g","rice 999999 g","unknown 90 g"] {try rejects{_ = try FoodCalculation.parse(text,references:refs)}}
    }
    check("manual weighed meal supports no photo and same calorie/protein aggregation") {
        var d=fixture();let e=TrackerEngine(document:d);d.meals.entries=[meal(e,"2026-06-08",600)]
        try d.validate();try expect(d.meals.entries[0].photos.isEmpty && d.meals.entries[0].missingPhotos==0)
        d.applyMealTotals(on:"2026-06-08",today:"2026-06-08")
        try expect(d.meals.totals("2026-06-08").kcal==320)
    }
    check("plan validation rejects overlapping windows, duplicate checkpoints and uncalibrated zero spray") {
        let d=fixture(),e=TrackerEngine(document:d);var p=plan(d)
        p.slots[1].startMinute=600;try rejects{try p.validate(engine:e,habits:d.habits)}
        p=plan(d);p.checkpoints=[.init(day:"2026-06-15",weight:88),.init(day:"2026-06-15",weight:87)];try rejects{try p.validate(engine:e,habits:d.habits)}
        p=plan(d);p.references[1].sprayGrams=0;try rejects{try p.validate(engine:e,habits:d.habits)}
    }
    check("checkpoints average daily means; same-day duplicate readings do not fake coverage") {
        let d=fixture(),e=TrackerEngine(document:d);var p=plan(d);p.checkpoints=[.init(day:"2026-06-15",weight:88)]
        func row(_ day:String,_ weight:Double) -> BodyMeasurement {BodyMeasurement(fields:["id":.text(UUID().uuidString),"createdAt":.number(e.date(day)!.timeIntervalSince1970*1000),"measuredWeight":.number(weight),"isManual":.bool(true)])}
        let one=[row("2026-06-15",90),row("2026-06-15",86)]
        try expect(DietCheckpointReport.build(plan:p,records:one,day:"2026-06-15",calendar:e.calendar).average==nil)
        let report=DietCheckpointReport.build(plan:p,records:one+[row("2026-06-14",88)],day:"2026-06-15",calendar:e.calendar)
        try expect(report.average==88 && report.label.hasPrefix("On pace"))
        try expect(DietCheckpointReport.build(plan:p,records:one,day:"2026-06-08",calendar:e.calendar).checkpoint==nil)
    }
    return(count,failures)
}
