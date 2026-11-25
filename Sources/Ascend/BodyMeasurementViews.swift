import SwiftUI
import AppKit
import Charts
import AscendCore
import UniformTypeIdentifiers

@MainActor final class BodyMeasurementStore: ObservableObject {
    @Published private(set) var archive = BodyArchive()
    @Published private(set) var message: String?
    @Published private(set) var failed = false
    let url: URL
    init(folder: URL) {
        url = folder.appendingPathComponent("body-measurements.json")
        do { archive = try BodyStorage.read(url) }
        catch { failed = true; message = "Body measurements could not be read. The file was preserved. \(error.localizedDescription)" }
    }
    func mergeCloud(_ records: [BodyMeasurement]) throws {
        archive = try BodyStorage.mergeRecords(records, to: url)
        failed = false; message = nil
    }
    func saveManual(id:String?=nil,kilograms:Double,date:Date) throws {
        let latest=try BodyStorage.read(url)
        let candidate=try latest.savingManual(id:id,kilograms:kilograms,date:date)
        try BodyStorage.saveManual(candidate,to:url);archive=candidate;failed=false;message=nil
    }
    /// Saves a weigh-in from the phone. False when that reading was already saved.
    func savePhoneWeight(id: String, kilograms: Double, date: Date) throws -> Bool {
        guard let candidate = try BodyStorage.read(url).savingPhoneWeight(id: id, kilograms: kilograms, date: date) else { return false }
        try BodyStorage.saveManual(candidate, to: url); archive = candidate; failed = false; message = nil
        return true
    }
    func deleteManual(_ id:String) throws {
        let candidate=try BodyStorage.read(url).deletingManual(id)
        try BodyStorage.saveManual(candidate,to:url);archive=candidate;failed=false;message=nil
    }
    func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = "Import Dr Trust measurements or a Cipher body backup"
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let data = try Data(contentsOf: source)
            let incoming = try DrTrustImport.read(data)
            let candidate = try archive.merging(incoming)
            guard candidate != archive else { failed = false; message = "These \(incoming.count) readings are already imported."; return }
            let alert = NSAlert()
            alert.messageText = "Import \(incoming.count) Dr Trust readings?"
            alert.informativeText = "Body measurements will contain \(candidate.records.count) readings. Existing readings with matching Dr Trust IDs are updated. A copy of the previous body file is saved before changes."
            alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            archive = try BodyStorage.importFile(data, to: url)
            failed = false; message = "Imported \(incoming.count) readings · \(archive.records.count) in your history."
        } catch { failed = true; message = "Import failed. \(error.localizedDescription)" }
    }
    func exportArchive() {
        let panel = NSSavePanel(); panel.title = "Export body measurements"
        panel.nameFieldStringValue = "Cipher-body-measurements.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(archive).write(to: destination, options: .atomic)
            failed = false; message = "Body measurement backup exported."
        } catch { failed = true; message = "Export failed. \(error.localizedDescription)" }
    }
}

private enum BodyDashboardMetric: String, CaseIterable, Identifiable {
    case weight, fat, muscle, water, bmi, bone, lean
    var id: String { rawValue }
    var title: String {
        switch self { case .weight: "Weight"; case .fat: "Body fat"; case .muscle: "Muscle mass"; case .water: "Body water"; case .bmi: "BMI"; case .bone: "Bone mass"; case .lean: "Fat-free mass" }
    }
    var field: String {
        switch self { case .weight: "measuredWeight"; case .fat: "bodyFatPercentage"; case .muscle: "muscleMass"; case .water: "bodyWater"; case .bmi: "bmi"; case .bone: "boneMass"; case .lean: "weightWithoutFat" }
    }
    var unit: String { switch self { case .fat, .water: "%"; case .bmi: ""; default: "kg" } }
    var symbol: String {
        switch self { case .weight: "scalemass"; case .fat: "circle.lefthalf.filled"; case .muscle: "figure.strengthtraining.traditional"; case .water: "drop.fill"; case .bmi: "square.grid.2x2"; case .bone: "figure.stand"; case .lean: "figure.core.training" }
    }
    var color: Color { switch self { case .water: Color(red: 0.38, green: 0.76, blue: 0.88); case .muscle, .lean: Color(red: 0.58, green: 0.80, blue: 0.73); default: Ink.accent } }
    func value(_ r: BodyMeasurement) -> Double? { r.value(field) }
}

struct BodyMeasurementPanel: View {
    @ObservedObject var store: BodyMeasurementStore
    @ObservedObject var cloud: DrTrustCloudService
    @State private var selected: String?
    @State private var metric = BodyDashboardMetric.weight
    @State private var chartDate: Date?
    @State private var showConnection = false
    @Environment(\.timeZone) private var timeZone
    private var records: [BodyMeasurement] { store.archive.records }
    private var reading: BodyMeasurement? { records.first { $0.id == selected } ?? records.last }
    private var index: Int { reading.flatMap { r in records.firstIndex { $0.id == r.id } } ?? 0 }
    private var previous: BodyMeasurement? { index > 0 ? records[index - 1] : nil }
    private var chartRecords: [BodyMeasurement] { records.filter { metric.value($0) != nil } }
    private var dateStyle: Date.FormatStyle { .dateTime.day().month(.abbreviated).year().bodyZone(timeZone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if let r = reading {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 26) {
                        BodyMapView()
                        snapshot(r).frame(minWidth: 490, maxWidth: .infinity)
                    }
                    VStack(spacing: 22) { snapshot(r); BodyMapView().frame(maxWidth: .infinity) }
                }
                history
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.bt(size: 11))
                    Text("Scale-reported estimates. Changes compare with the previous recorded reading, not a daily average. Missing values stay blank.")
                        .font(.bt(size: 11)).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Ink.muted)
            } else {
                HStack(spacing: 20) {
                    Image(systemName: "scalemass").font(.bt(size: 36)).foregroundStyle(Ink.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your next reading starts here.").font(.bt(size: 19, weight: .medium))
                        Text("Connect Dr Trust to bring in your weight and body-composition history, or import a saved body backup.")
                            .font(.bt(size: 13)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                }.padding(.vertical, 24)
                Button("Connection & data") { showConnection = true }
            }
            Divider().overlay(Ink.line)
            DisclosureGroup(isExpanded: $showConnection) {
                VStack(alignment: .leading, spacing: 12) {
                    DrTrustCloudPanel(cloud: cloud)
                    HStack {
                        Button("Import body JSON…") { store.chooseImport() }
                        Button("Export body backup…") { store.exportArchive() }.disabled(records.isEmpty)
                        Spacer()
                    }
                    Text("Body readings have their own backup. They are not included in the main tracker backup.")
                        .font(.bt(size: 11)).foregroundStyle(Ink.muted)
                    Link("Body artwork · MIT license", destination: URL(string: "https://github.com/giavinh79/react-body-highlighter")!)
                        .font(.bt(size: 11))
                }.padding(.top, 12)
            } label: {
                HStack {
                    Text("Connection & data").font(.bt(size: 12, weight: .medium))
                    Spacer()
                    Text(cloud.connected ? (cloud.automatic ? "Automatic sync on" : "Automatic sync paused") : "Not connected")
                        .font(.bt(size: 11)).foregroundStyle(Ink.muted)
                }
            }.tint(Ink.muted)
            if let message = store.message { Text(message).font(.bt(size: 12)).foregroundStyle(store.failed ? .orange : Ink.muted) }
            if cloud.failed, let status = cloud.status, !showConnection { Text(status).font(.bt(size: 12)).foregroundStyle(.orange) }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Ink.line))
        .onChange(of: chartDate) { _, date in
            guard let date, let nearest = chartRecords.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return }
            selected = nearest.id
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("BODY COMPOSITION").font(.bt(size: 10, weight: .medium, design: .monospaced)).tracking(1.8).foregroundStyle(Ink.accent)
                Text("Your body, over time.").font(.bt(size: 25, weight: .semibold)).tracking(-0.5)
                HStack(spacing: 6) {
                    Text("Dr Trust 360"); Text("·"); Text("\(records.count) readings")
                    if let date = cloud.lastSync { Text("·"); Text("Synced \(date.formatted(.dateTime.hour().minute().bodyZone(timeZone)))") }
                }.font(.bt(size: 11)).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 4)
            if !records.isEmpty {
                Button { cloud.sync() } label: {
                    if cloud.busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise").frame(width: 22, height: 22) }
                }.buttonStyle(.borderless).disabled(!cloud.connected || cloud.busy || cloud.needsLogin).help("Sync Dr Trust now").accessibilityLabel("Sync Dr Trust now")
            }
            Menu {
                Button("Import body JSON…") { store.chooseImport() }
                Button("Export body backup…") { store.exportArchive() }.disabled(records.isEmpty)
                Divider()
                Button("Connection settings") { showConnection = true }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).fixedSize().help("Body data and connection settings").accessibilityLabel("Body data options")
        }
    }
    private func snapshot(_ r: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(Ink.accent).frame(width: 5, height: 5)
                    Text(r.id == records.last?.id ? "LATEST STORED READING" : "HISTORICAL READING")
                        .font(.bt(size: 9, weight: .medium, design: .monospaced)).tracking(1.1)
                }.foregroundStyle(Ink.muted)
                Spacer()
                readingPicker
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(r.kilograms.formatted(.number.precision(.fractionLength(2))))
                    .font(.bt(size: 58, weight: .semibold, design: .rounded)).tracking(-2).monospacedDigit()
                Text("kg").font(.bt(size: 20)).foregroundStyle(Ink.muted)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    delta(.weight, r, size: 13)
                    Text(previous == nil ? "First recorded reading" : "vs previous reading")
                        .font(.bt(size: 10)).foregroundStyle(Ink.muted)
                }
            }
            Text("Recorded \(r.date.formatted(dateStyle)) at \(r.date.formatted(.dateTime.hour().minute().bodyZone(timeZone)))")
                .font(.bt(size: 11)).foregroundStyle(Ink.muted).padding(.top, -10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 10), count: 3), spacing: 10) {
                ForEach(BodyDashboardMetric.allCases.filter { $0 != .weight }) { m in metricCard(m, r) }
            }
        }
    }
    private var readingPicker: some View {
        HStack(spacing: 3) {
            Button { if index > 0 { selected = records[index - 1].id } } label: { Image(systemName: "chevron.left").frame(width: 22, height: 24) }
                .buttonStyle(.plain).disabled(index == 0).accessibilityLabel("Previous body reading")
            Picker("Body reading", selection: Binding(get: { reading?.id ?? "" }, set: { selected = $0 })) {
                ForEach(records.reversed()) { row in Text(row.date.formatted(dateStyle) + " · " + row.date.formatted(.dateTime.hour().minute().second().bodyZone(timeZone))).tag(row.id) }
            }.labelsHidden().pickerStyle(.menu).fixedSize().font(.bt(size: 11))
            Button { if index + 1 < records.count { selected = records[index + 1].id } } label: { Image(systemName: "chevron.right").frame(width: 22, height: 24) }
                .buttonStyle(.plain).disabled(index + 1 >= records.count).accessibilityLabel("Next body reading")
        }
    }
    private func metricCard(_ m: BodyDashboardMetric, _ r: BodyMeasurement) -> some View {
        Button { metric = m; chartDate = nil } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: m.symbol).foregroundStyle(m.color).font(.bt(size: 11))
                    Text(m.title).foregroundStyle(Ink.muted).font(.bt(size: 11))
                    Spacer(minLength: 0)
                    if metric == m { Circle().fill(m.color).frame(width: 4, height: 4) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.value(r).map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                        .font(.bt(size: 23, weight: .medium)).tracking(-0.5).monospacedDigit()
                    Text(m.unit).font(.bt(size: 11)).foregroundStyle(Ink.muted)
                }
                delta(m, r, size: 10)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(metric == m ? m.color.opacity(0.08) : Color.white.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(metric == m ? m.color.opacity(0.35) : Ink.line.opacity(0.65)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).help("Show \(m.title.lowercased()) history")
            .accessibilityLabel("\(m.title), \(m.value(r).map { String(format: "%.2f", $0) } ?? "not recorded") \(m.unit). Show history.")
    }
    private func delta(_ m: BodyDashboardMetric, _ r: BodyMeasurement, size: CGFloat) -> some View {
        let change = previous.flatMap { p in m.value(p).flatMap { old in m.value(r).map { $0 - old } } }
        return HStack(spacing: 3) {
            if let change {
                Image(systemName: abs(change) < 0.005 ? "minus" : change > 0 ? "arrow.up.right" : "arrow.down.right")
                Text(abs(change).formatted(.number.precision(.fractionLength(2))) + (m.unit == "%" ? " pp" : m.unit.isEmpty ? "" : " \(m.unit)"))
            } else { Text("No earlier comparison") }
        }.font(.bt(size: size, weight: .medium)).foregroundStyle(change == nil ? Ink.muted.opacity(0.7) : m.color)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(metric.title) history").font(.bt(size: 15, weight: .medium))
                    Text("\(records.first?.date.formatted(dateStyle) ?? "") – \(records.last?.date.formatted(dateStyle) ?? "")")
                        .font(.bt(size: 10)).foregroundStyle(Ink.muted)
                }
                Spacer()
                Picker("Chart metric", selection: $metric) {
                    ForEach(BodyDashboardMetric.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).fixedSize().font(.bt(size: 11))
            }
            if chartRecords.isEmpty {
                Text("No \(metric.title.lowercased()) values were recorded.").font(.bt(size: 12)).foregroundStyle(Ink.muted).frame(height: 150)
            } else {
                Chart {
                    ForEach(chartRecords) { row in
                        if let value = metric.value(row) {
                            AreaMark(x: .value("Date", row.date), yStart: .value(metric.unit, chartDomain.lowerBound), yEnd: .value(metric.title, value))
                                .foregroundStyle(LinearGradient(colors: [metric.color.opacity(0.16), metric.color.opacity(0.005)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Date", row.date), y: .value(metric.title, value)).foregroundStyle(metric.color).lineStyle(StrokeStyle(lineWidth: 2))
                            PointMark(x: .value("Date", row.date), y: .value(metric.title, value))
                                .foregroundStyle(metric.color).symbolSize(row.id == reading?.id ? 65 : 20)
                        }
                    }
                    if let r = reading, let value = metric.value(r) {
                        RuleMark(x: .value("Selected reading", r.date)).foregroundStyle(metric.color.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        PointMark(x: .value("Selected date", r.date), y: .value(metric.title, value)).foregroundStyle(metric.color).symbolSize(65)
                    }
                }
                .chartXSelection(value: $chartDate)
                .chartYScale(domain: chartDomain)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(Ink.line.opacity(0.65)); AxisValueLabel().foregroundStyle(Ink.muted) } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel().foregroundStyle(Ink.muted) } }
                .chartYAxisLabel(metric.unit, position: .trailing)
                .frame(height: 170)
                .accessibilityLabel("\(metric.title) history, \(chartRecords.count) recorded values")
                HStack {
                    Text("Drag across the chart to inspect a reading").font(.bt(size: 10)).foregroundStyle(Ink.muted)
                    Spacer()
                    if let r = reading, let value = metric.value(r) { Text("\(value.formatted(.number.precision(.fractionLength(2)))) \(metric.unit) · \(r.date.formatted(.dateTime.day().month(.abbreviated).bodyZone(timeZone)))").font(.bt(size: 10, weight: .medium)).foregroundStyle(metric.color) }
                }
            }
        }.padding(18).background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
    private var chartDomain: ClosedRange<Double> {
        let values = chartRecords.compactMap { metric.value($0) }
        let lower = values.min() ?? 0, upper = values.max() ?? 1
        let padding = max((upper - lower) * 0.25, metric == .weight ? 0.5 : 0.2)
        return max(0, lower - padding)...(upper + padding)
    }
}

private extension Date.FormatStyle {
    func bodyZone(_ zone: TimeZone) -> Self { var result = self; result.timeZone = zone; return result }
}
