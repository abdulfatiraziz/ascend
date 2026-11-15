import Foundation
import AscendCore

/// Builds the phone's copy of the Brief, Condition › Screen time, Notes and Dossier, from the same facts the Mac screens use.
extension TrackerStore {
    func phoneBrief(now: Date = Date()) -> PhoneBrief {
        var b = PhoneBrief()
        let engine = self.engine

        // Brief › Goals
        let facts = MissionFacts(store: self)
        let ms = missions.missions
        b.missions = ms.map { m in
            PhoneMission(id: m.id, codename: m.codename, title: m.title,
                         due: dateText(m.due, engine: engine, pattern: "d MMM yyyy"),
                         progress: m.progress(facts.value) ?? 0,
                         status: Missions.status(m, value: facts.value, today: today).rawValue)
        }
        b.orders = Missions.orders(ms, value: facts.value, today: today).map {
            PhoneOrder(mission: $0.missionID, title: $0.target.title, line: $0.line, logged: $0.value != nil)
        }
        let all = ms.flatMap(\.targets).filter { !$0.checklist }
        b.targets = all.count
        b.measured = all.filter { facts.value($0) != nil }.count
        b.behind = Missions.orders(ms, value: facts.value, today: today, limit: 99).filter { $0.value != nil }.count
        b.milestones = ms.flatMap(\.targets).filter { $0.checklist && ($0.current ?? 0) >= 1 }.count

        // Brief › Today
        let brief = BriefFacts(store: self, day: today)
        b.focus = brief.focusLine
        b.focusDetail = brief.focusDetail
        b.daysLeft = brief.daysLeft

        // Brief › Routine
        let r = RoutineFacts(store: self, now: now)
        b.routineLine = "Tonight: lights out by \(HealthReport.clock(document.routine.bedMinute))."
        b.routine = r.ahead.map { e in
            let current = e.kind == .meal && r.nowMinute >= e.minute && r.nowMinute < (e.endMinute ?? e.minute)
            let status = e.done ? (e.kind == .meds ? "TAKEN" : "LOGGED") : current ? "OPEN" : RoutineFacts.span(e.minute - r.nowMinute)
            let detail = current ? "Window till \(HealthReport.clock(e.endMinute ?? e.minute)) · \(e.detail)" : e.detail
            return PhoneRoutineItem(time: HealthReport.clock(e.minute), title: e.title, detail: detail, status: status,
                                    kind: e.kind.rawValue, done: e.done, current: current)
        }
        b.earlier = r.earlier.map(\.text)

        // Condition › Screen time: the phone's days as the Mac has them.
        if let phone = screenTime.archive.devices.filter({ $0.source != "macKnowledge" }).max(by: { $0.lastSync < $1.lastSync }) {
            let yesterday = engine.adding(-1, to: today)
            var shownKey = yesterday
            var shown = Condition.day(phone, key: yesterday, engine: engine)
            if shown?.screenSeconds == nil, let last = phone.days.last(where: { $0.screenSeconds != nil && engine.key(Date(timeIntervalSince1970: $0.start + 60)) < today }) {
                shown = last; shownKey = engine.key(Date(timeIntervalSince1970: last.start + 60))
            }
            if let shown, let seconds = shown.screenSeconds {
                b.screenLine = "\(HealthReport.duration(seconds / 60)) on the phone " + (shownKey == yesterday ? "yesterday." : "on \(dateText(shownKey, engine: engine, pattern: "d MMM")).")
                b.screenDays = (0..<7).reversed().map { i in
                    let k = engine.adding(-i, to: shownKey)
                    return PhoneScreenDay(label: dateText(k, engine: engine, pattern: i == 6 ? "d MMM" : "d"),
                                          minutes: Condition.day(phone, key: k, engine: engine)?.screenSeconds.map { $0 / 60 }, shown: i == 0)
                }
                b.topApps = shown.apps.sorted { $0.seconds > $1.seconds }.prefix(5).map { PhoneScreenApp(name: $0.label, minutes: $0.seconds / 60) }
            }
        }

        // Field log › Notes
        b.notes = document.notes.sorted.prefix(30).map {
            PhoneNote(kind: $0.kind.label, title: $0.title, body: PhoneNote.clip($0.body),
                      date: dateText($0.day, engine: engine, pattern: "d MMM"), pinned: $0.pinned)
        }

        // Dossier
        let week = WeekFacts(store: self)
        let status = week.status, w = week.thisWeek
        let rewards = lifestyle.lifestyle.rewards
        b.clearance = PhoneClearance(
            level: status.level.rawValue,
            next: status.level.next.map { _ in "Next: \(status.level.nextRule) · streak \(status.streak)/\(status.level.weeksToNext)" } ?? status.level.nextRule,
            week: "Gym \(w.gym)/3 · check-ins \(Int((w.checkIns * 100).rounded()))% · by 1 am \(w.nightsByOne)/\(max(w.nightsKnown, 0))",
            marks: ClearanceLevel.allCases.map(\.mark), ranks: ClearanceLevel.allCases.map(\.rank),
            rewards: ClearanceLevel.allCases.map { rewards[$0.mark] ?? "Set a reward" })
        if let m = week.debriefMonday {
            let memo = Debrief.compose(week.debriefWeek(m))
            b.memo = PhoneMemo(week: "Week of " + dateText(m, engine: engine, pattern: "d MMM"), wins: memo.wins, misses: memo.misses, order: memo.order)
        }
        b.sections = DossierSection.allCases.map { s in
            PhoneDossierSection(title: s.title, blurb: s.blurb, items: lifestyle.lifestyle.items(in: s).map {
                PhoneDossierItem(title: $0.title, detail: $0.detail, tag: $0.tag, placeholder: $0.placeholder, progress: $0.progress)
            })
        }
        // Brief › Today: the Mac's "Ascend is tracking" card, the score under it, and what was eaten.
        b.tracking = TodayGlanceCard.lines(store: self, day: today).map { l in
            let state: String
            switch l.state { case .done: state = "done"; case .going: state = "going"; case .waiting: state = "waiting"; case .missed: state = "missed" }
            return PhoneGlance(title: l.title, state: state, value: l.value, note: l.note, ratio: l.ratio.map { min(1, max(0, $0)) })
        }
        let score = engine.score(on: today), target = document.cycle.target
        let left = score.remaining(target: target)
        b.score = PhoneScore(completed: score.completed, scheduled: score.scheduled,
                             line: score.scheduled == 0 ? "nothing scheduled" : "done today · \(Int(target * 100))% is the mission · " + (left > 0 ? "\(left) to go" : "hit"))
        let totals = document.meals.totals(today), mealHabits = document.mealHabits
        let cal = engine.calendar
        b.food = PhoneFood(kcal: totals.kcal, protein: totals.protein, carbs: totals.carbs, fat: totals.fat,
                           kcalLimit: mealHabits.calories.flatMap { engine.target(for: $0, on: today)?.maximum },
                           proteinGoal: mealHabits.protein.flatMap { engine.target(for: $0, on: today)?.minimum },
                           pending: totals.pending,
                           meals: document.meals.on(today).map { m in
                               let at = Date(timeIntervalSince1970: m.takenAt)
                               let v = m.values
                               let name = m.estimate?.name ?? ""
                               return PhoneMealLine(time: HealthReport.clock(cal.component(.hour, from: at) * 60 + cal.component(.minute, from: at)),
                                                    title: !name.isEmpty ? name : (m.note.isEmpty ? "Meal" : m.note),
                                                    kcal: v.kcal, protein: v.protein, carbs: v.carbs, fat: v.fat, confirmed: m.confirmed)
                           })
        return b
    }
}
