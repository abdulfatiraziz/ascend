import SwiftUI
import LocalAuthentication

/// Eyes only: the vault over the window. Sealing closes a gold iris onto a safe dial; Touch ID (or the Mac
/// password) spins the dial, stamps CLEARED and opens the iris. Reduce Motion skips the moves.
struct EyesOnlyCover: View {
    let onOpen: () -> Void
    private enum Phase { case sealing, sealed, checking, denied, cleared }
    @State private var phase: Phase = .sealing
    @State private var iris: CGFloat = 1        // 1 = hole fills the window (app visible), 0 = closed
    @State private var spin: Double = 0
    @State private var shake: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let full = hypot(g.size.width, g.size.height) + 40
            ZStack {
                LitFelt()
                card.offset(x: shake).scaleEffect(phase == .sealing ? 0.92 : 1).opacity(phase == .sealing ? 0 : 1)
            }
            .mask {
                Rectangle().overlay(Circle().frame(width: full * iris, height: full * iris).blendMode(.destinationOut)).compositingGroup()
            }
            .overlay {
                if iris > 0.001 && iris < 0.999 {
                    Circle().stroke(Ink.accent, lineWidth: 3).frame(width: full * iris, height: full * iris)
                        .shadow(color: Ink.lamp.opacity(0.8), radius: 12).allowsHitTesting(false)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onAppear(perform: seal)
    }

    private var card: some View {
        VStack(spacing: 16) {
            stamp
            ZStack {
                Bezel(progress: phase == .cleared ? 1 : 0, lineWidth: 3, color: Ink.lamp).rotationEffect(.degrees(spin))
                Image(systemName: phase == .cleared ? "lock.open.fill" : "touchid")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(phase == .denied ? Ink.offTrack : phase == .cleared ? Ink.lamp : Ink.accent)
                    .symbolEffect(.pulse, isActive: phase == .checking)
            }.frame(width: 120, height: 120)
            Text(phase == .cleared ? "Welcome back, Abdul." : "Cipher is sealed.").font(.bt(size: 30)).foregroundStyle(Ink.ivory)
            Text(phase == .denied ? "Not recognised. Try again." : "Numbers, photos and logs are hidden until Touch ID or your Mac password opens it.")
                .font(.bt(size: 12)).foregroundStyle(phase == .denied ? Ink.offTrack : Ink.muted).multilineTextAlignment(.center)
            Button(action: unlock) {
                Label("Unlock with Touch ID  ⌘⇧E", systemImage: "touchid").font(.bt(size: 12, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 9)
            }
            .buttonStyle(.plain).background(Ink.accent, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(Ink.background)
            .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(phase == .checking || phase == .cleared)
        }
        .padding(36).frame(width: 470)
        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke((phase == .cleared ? Ink.lamp : Ink.accent).opacity(0.35)))
    }

    private var stamp: some View {
        let text = phase == .cleared ? "CLEARED" : phase == .denied ? "ACCESS DENIED" : "EYES ONLY"
        let color = phase == .cleared ? Ink.lamp : phase == .denied ? Ink.offTrack : Ink.accent
        let caption = phase == .cleared ? "FILE 0075 · ACCESS GRANTED" : phase == .denied ? "FILE 0075 · NOT RECOGNISED" : "FILE 0075 · CLEARANCE REQUIRED"
        // Engraved, not stamped: spaced serif capitals between hairline gold rules, like a watch dial or a cufflink box.
        return VStack(spacing: 9) {
            Text(caption).font(.bt(size: 9, design: .monospaced)).tracking(2.4).foregroundStyle(Ink.goldDim)
            HStack(spacing: 12) {
                rule(color, leading: true)
                Text(text).font(.custom(Typeface.serif, fixedSize: 21).weight(.semibold)).tracking(7).foregroundStyle(color)
                    .contentTransition(.opacity).fixedSize()
                rule(color, leading: false)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
    }
    /// A hairline that fades in towards the title, ending in a small diamond.
    private func rule(_ color: Color, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if !leading { diamond(color) }
            LinearGradient(colors: leading ? [.clear, color.opacity(0.8)] : [color.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 64, height: 1)
            if leading { diamond(color) }
        }
    }
    private func diamond(_ color: Color) -> some View { Rectangle().fill(color).frame(width: 5, height: 5).rotationEffect(.degrees(45)) }

    private func seal() {
        guard !reduceMotion else { iris = 0; phase = .sealed; return }
        withAnimation(.easeInOut(duration: 0.7)) { iris = 0 }
        withAnimation(.easeOut(duration: 1.1)) { spin = -180 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { phase = .sealed } }
    }

    private func unlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Stay sealed"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { cleared(); return }
        phase = .checking
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open Cipher") { ok, _ in
            DispatchQueue.main.async { ok ? cleared() : denied() }
        }
    }

    private func denied() {
        phase = .denied
        guard !reduceMotion else { return }
        for (i, x) in [14, -12, 9, -6, 3, 0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { withAnimation(.linear(duration: 0.06)) { shake = CGFloat(x) } }
        }
    }

    private func cleared() {
        guard !reduceMotion else { onOpen(); return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { phase = .cleared }
        withAnimation(.easeInOut(duration: 0.9)) { spin += 360 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { withAnimation(.easeIn(duration: 0.75)) { iris = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) { onOpen() }
    }
}
