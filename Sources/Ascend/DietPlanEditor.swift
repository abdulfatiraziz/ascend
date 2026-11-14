import AscendCore
import SwiftUI

struct DietPlanEditor: View {
    @ObservedObject var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: DietPlan
    @State private var limits: [String]
    @State private var sweets: String
    @State private var error: String?
    init(store: TrackerStore) {
        self.store=store
        let plan=store.document.diet ?? DietPlan(effectiveDay:store.today)
        _plan=State(initialValue:plan);_sweets=State(initialValue:plan.sweetOptions.joined(separator:"\n"))
        let revision=store.document.mealHabits.calories?.latest
        _limits=State(initialValue:(1...7).map { revision?.target(weekday:$0)?.maximum.map { String($0) } ?? "" })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Your diet plan").font(.bt(size: 24, weight: .semibold)); Spacer(); Button("Cancel") { dismiss() } }
            Text("Meal windows, food references and checkpoints are your editable plan. Calorie changes start today; earlier habit revisions are preserved.").font(.bt(size: 12)).foregroundStyle(Ink.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    budgetEditor
                    slotEditor
                    sweetsEditor
                    referencesEditor
                    checkpointsEditor
                }.padding(.trailing, 6)
            }
            if let error { Text(error).font(.bt(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let e=store.saveError { Text(e).foregroundStyle(.orange) }
            HStack { Spacer(); PrimaryButton(label:"Save plan") { save() } }
        }.padding(24).frame(width:820,height:740).background(Ink.background).foregroundStyle(.white).tint(Ink.accent)
          .environment(\.locale, Locale(identifier:"en_US"))
    }
    private var budgetEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("WEEKDAY CALORIE TARGETS")
            if store.document.mealHabits.calories == nil { Text("Add a calorie habit measured in kcal first. Meal planning can still be saved.").font(.bt(size: 11)).foregroundStyle(Ink.muted) }
            else {
                HStack {
                    ForEach(1...7,id:\.self) { weekday in
                        VStack(alignment:.leading,spacing:5) {
                            Text(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][weekday-1]).font(.bt(size: 11))
                            TextField("kcal",text:$limits[weekday-1]).textFieldStyle(.roundedBorder).frame(width:82)
                        }
                    }
                }
                Text("Weekly total: \(limits.compactMap { Double($0.replacingOccurrences(of:",",with:"")) }.reduce(0,+).pretty) kcal · applies to the existing calorie habit on all seven days.").font(.bt(size: 11)).foregroundStyle(Ink.muted)
            }
        }
    }
    private var slotEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Kicker("MEAL TEMPLATE · NONOVERLAPPING WINDOWS"); Spacer(); Button("Add slot") { addSlot() }.disabled((plan.slots.map(\.endMinute).max() ?? 0)>=1440) }
            ForEach($plan.slots) { $slot in
                DietSlotEditorRow(slot:$slot,engine:store.engine) { plan.slots.removeAll{$0.id==slot.id} }
            }
        }
    }
    private var sweetsEditor: some View {
        VStack(alignment:.leading,spacing:10) {
            Kicker("SWEET SLOT AND EXISTING HABIT")
            Picker("Outside-window sweets count against",selection:$plan.sweetsHabitID) {
                Text("No linked habit").tag(nil as UUID?)
                ForEach(store.document.habits.filter{$0.kind == .check && $0.archivedDay == nil}) { h in Text(h.latest.title).tag(Optional(h.id)) }
            }
            Text("Sweet choices, one per line").font(.bt(size: 11)).foregroundStyle(Ink.muted)
            TextEditor(text:$sweets).font(.bt(size:12)).frame(height:90).padding(6).background(Ink.panel,in:RoundedRectangle(cornerRadius:8))
            Text("Only meals explicitly tagged Sweet are checked. A confirmed sweet outside every sweet window makes the linked habit incomplete; it never marks a day successful automatically.").font(.bt(size: 11)).foregroundStyle(Ink.muted)
        }
    }
    private var referencesEditor: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Kicker("FOOD REFERENCES · PER 100 G");Spacer();Button("Add food") { plan.references.append(FoodReference(name:"",kcal:0)) } }
            ForEach($plan.references) { $food in DietFoodEditorRow(food:$food) { plan.references.removeAll{$0.id==food.id} } }
            Text("Leave tablespoon/spray grams blank until calibrated. All nutrition is editable; these are planning references, not photo estimates.").font(.bt(size: 11)).foregroundStyle(Ink.muted)
        }
    }
    private var checkpointsEditor: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Kicker("WEIGHT CHECKPOINTS");Spacer();Button("Add checkpoint") { addCheckpoint() } }
            ForEach(plan.checkpoints.indices,id:\.self) { index in
                HStack {
                    DatePicker("Date",selection:Binding(get:{store.engine.date(plan.checkpoints[index].day) ?? Date()},set:{plan.checkpoints[index].day=store.engine.key($0)}),displayedComponents:.date).frame(width:240)
                    TextField("kg",value:$plan.checkpoints[index].weight,format:.number).textFieldStyle(.roundedBorder).frame(width:90)
                    Text("kg").foregroundStyle(Ink.muted);Spacer();Button("Remove") { plan.checkpoints.remove(at:index) }
                }
            }
            HStack { Text("On-pace tolerance ± kg");TextField("kg",value:$plan.checkpointTolerance,format:.number).textFieldStyle(.roundedBorder).frame(width:75) }.font(.bt(size: 11))
        }
    }
    private func addSlot() {
        let start=plan.slots.map(\.endMinute).max() ?? 0
        guard start<1440 else{return}
        plan.slots.append(DietSlot(name:"New meal",startMinute:start,endMinute:min(1440,start+60)))
    }
    private func addCheckpoint() {
        let last=plan.checkpoints.max{$0.day<$1.day}
        let date=last.flatMap{store.engine.date($0.day)} ?? store.engine.date(store.today)!
        let next=store.engine.calendar.date(byAdding:.day,value:7,to:date)!
        plan.checkpoints.append(.init(day:store.engine.key(next),weight:last?.weight ?? 80))
    }
    private func save() {
        var candidate=plan
        candidate.sweetOptions=sweets.split(separator:"\n").map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
        var targets:[Int:Double]?
        if store.document.mealHabits.calories != nil {
            let values=limits.compactMap { Double($0.replacingOccurrences(of:",",with:"")) }
            guard values.count==7,values.allSatisfy({$0.isFinite && $0>0 && $0<=10000}) else {error="Enter a positive calorie limit for each weekday.";return}
            targets=Dictionary(uniqueKeysWithValues:(1...7).map{($0,values[$0-1])})
        }
        do {try candidate.validate(engine:store.engine,habits:store.document.habits)} catch {self.error=error.localizedDescription;return}
        if store.saveDietPlan(candidate,weekdayLimits:targets){dismiss()}
    }
}
private struct DietSlotEditorRow: View {
    @Binding var slot: DietSlot
    let engine: TrackerEngine
    var remove: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack { TextField("Name",text:$slot.name).textFieldStyle(.roundedBorder);Spacer();Button("Remove",action:remove) }
            TextField("Foods and gram amounts",text:$slot.portion,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
            HStack {
                DatePicker("From",selection:timeBinding(end:false),displayedComponents:.hourAndMinute)
                DatePicker("Until",selection:timeBinding(end:true),displayedComponents:.hourAndMinute)
                TextField("Planned kcal",text:optionalNumber($slot.kcal)).textFieldStyle(.roundedBorder).frame(width:100)
                TextField("Protein g",text:optionalNumber($slot.protein)).textFieldStyle(.roundedBorder).frame(width:90)
            }.font(.bt(size:12))
            HStack { Toggle("Sweet window",isOn:$slot.sweet);Toggle("Café can replace this slot",isOn:$slot.cafeReplacement) }.font(.bt(size: 11))
        }.padding(12).background(Ink.panel,in:RoundedRectangle(cornerRadius:10))
    }
    private func timeBinding(end:Bool) -> Binding<Date> {
        Binding(get:{
            let minute=end ? slot.endMinute:slot.startMinute
            return engine.calendar.date(bySettingHour:minute%1440/60,minute:minute%60,second:0,of:Date())!
        },set:{date in let value=engine.minute(date);if end{slot.endMinute=value==0 ? 1440:value}else{slot.startMinute=value}})
    }
}
private func optionalNumber(_ number: Binding<Double?>) -> Binding<String> {
    Binding(get:{number.wrappedValue.map{String($0)} ?? ""},set:{number.wrappedValue=Double($0)})
}
private struct DietFoodEditorRow: View {
    @Binding var food: FoodReference
    var remove: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { TextField("Food name",text:$food.name).textFieldStyle(.roundedBorder);Spacer();Button("Remove",action:remove) }
            HStack {
                field("kcal",$food.kcal);field("Protein g",$food.protein);field("Carbs g",$food.carbs);field("Fat g",$food.fat)
                VStack(alignment:.leading){Text("g / tbsp").font(.caption2);TextField("optional",text:optionalNumber($food.tablespoonGrams)).textFieldStyle(.roundedBorder)}
                VStack(alignment:.leading){Text("g / spray").font(.caption2);TextField("calibrate",text:optionalNumber($food.sprayGrams)).textFieldStyle(.roundedBorder)}
            }
        }.padding(12).background(Ink.panel,in:RoundedRectangle(cornerRadius:10))
    }
    private func field(_ title:String,_ value:Binding<Double>) -> some View { VStack(alignment:.leading){Text(title).font(.caption2);TextField(title,value:value,format:.number).textFieldStyle(.roundedBorder)} }
}
