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
            Text(phase == .cleared ? "Welcome back, Abdul." : "Ascend is sealed.").font(.bt(size: 30)).foregroundStyle(Ink.ivory)
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
        let color = phase == .cleared ? Ink.onTrack : Ink.offTrack
        return Text(text).font(.bt(size: 13, weight: .bold, design: .monospaced)).tracking(5)
            .foregroundStyle(color).padding(.horizontal, 16).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 2))
            .rotationEffect(.degrees(phase == .cleared ? 3 : -4))
            .scaleEffect(phase == .cleared ? 1.08 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: phase)
    }

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
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open Ascend") { ok, _ in
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
