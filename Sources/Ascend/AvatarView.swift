import SwiftUI
import AppKit
import AscendCore

/// Native presentation of supplied portrait renders. Cropping is display-only;
/// the original pixels remain bundled intact. These images are not a rotatable mesh.
struct AvatarView: View {
    var progress: Double
    var evolution: Double
    var finish: String
    var previewStage: AvatarStage? = nil
    var compact = false
    @Binding var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var stage: AvatarStage { .resolve(evolution: evolution, appearance: finish, preview: previewStage) }
    private var accent: Color {
        switch stage {
        case .obsidian: Color(red: 0.64, green: 0.48, blue: 0.96)
        case .titanium: Color(red: 0.63, green: 0.84, blue: 0.91)
        case .ascendant: Color(red: 0.72, green: 0.58, blue: 1)
        }
    }
    private static let images: [AvatarStage: NSImage] = Dictionary(uniqueKeysWithValues: AvatarStage.allCases.compactMap { stage -> (AvatarStage, NSImage)? in
        let folder = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.resourceURL?.appendingPathComponent("Ascend_Ascend.bundle/Portraits")
            : Bundle.module.resourceURL?.appendingPathComponent("Portraits")
        guard let url = folder?.appendingPathComponent("\(stage.resource).png"), let image = NSImage(contentsOf: url) else { return nil }
        return (stage, image)
    })
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !compact {
                    Ellipse().fill(accent.opacity(0.15 + min(1, max(0, progress)) * 0.07)).blur(radius: 45)
                        .frame(width: geometry.size.width * 0.67, height: geometry.size.height * 0.72)
                    Circle().stroke(accent.opacity(0.10), lineWidth: 1)
                        .frame(width: min(geometry.size.width * 0.80, geometry.size.height * 0.92))
                }
                ForEach(AvatarStage.allCases) { item in
                    if let image = Self.images[item] {
                        portrait(image, size: geometry.size)
                            .opacity(item == stage ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.85), value: stage)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your avatar, \(stage.rawValue)\(previewStage == nil ? "" : ", cosmetic preview")")
        .onAppear { error = Self.images.count == AvatarStage.allCases.count ? nil : "Avatar portraits are missing from this build." }
    }
    private func portrait(_ image: NSImage, size: CGSize) -> some View {
        // Original 458×768 renders contain labels above/below the artwork.
        // A tighter face crop keeps the compact menu readable.
        let top: CGFloat = 48
        let cropHeight: CGFloat = compact ? 600 : 672
        let width = min(size.width, size.height * 458 / cropHeight)
        let height = width * cropHeight / 458
        return Image(nsImage: image).resizable().interpolation(.high)
            .frame(width: width, height: width * 768 / 458)
            .offset(y: -top * width / 458)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.035), .init(color: .black, location: 0.94), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}
