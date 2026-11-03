import Foundation
import AscendCore

// Explicit paths only: this utility never discovers or rewrites the live tracker/watch files.
guard CommandLine.arguments.count == 3 else {
    print("Usage: AscendBodyImport <drtrust-export.json> <body-measurements.json>")
    exit(2)
}
do {
    let source = URL(fileURLWithPath: CommandLine.arguments[1])
    let target = URL(fileURLWithPath: CommandLine.arguments[2])
    guard source.standardizedFileURL != target.standardizedFileURL else { throw ValidationError(message: "Choose a destination separate from the source export.") }
    let archive = try BodyStorage.importFile(Data(contentsOf: source), to: target)
    print("Saved \(archive.records.count) body measurements to \(target.path)")
} catch { fputs("Import failed: \(error.localizedDescription)\n", stderr); exit(1) }
