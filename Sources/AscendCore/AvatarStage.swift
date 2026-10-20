import Foundation

public enum AvatarStage: String, CaseIterable, Identifiable, Sendable {
    case obsidian = "Obsidian", titanium = "Titanium", ascendant = "Ascendant"
    public var id: String { rawValue }
    public var resource: String { rawValue.lowercased() }
    public var ordinal: Int { Self.allCases.firstIndex(of: self)! + 1 }

    /// Evolution is earned check-ins divided by the cycle's required check-ins.
    /// Empty plans and nonfinite inputs start at Obsidian; elapsed days never unlock a form.
    public static func earned(_ evolution: Double) -> Self {
        guard evolution.isFinite else { return .obsidian }
        if evolution >= 1 { return .ascendant }
        if evolution >= 0.5 { return .titanium }
        return .obsidian
    }
    public static func resolve(evolution: Double, appearance: String, preview: Self? = nil) -> Self {
        preview ?? Self(rawValue: appearance) ?? earned(evolution)
    }
}
