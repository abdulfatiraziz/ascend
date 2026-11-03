import AppKit
import Combine
import Carbon.HIToolbox

/// F7 has no binding in Ascend. An unhandled (including stuck/repeating) F7
/// otherwise reaches NSDatePicker/NSWindow and plays the macOS error sound.
/// This local monitor never changes another app's input or system media events.
@MainActor final class FunctionKeyFilter: ObservableObject {
    private var monitor: Any?
    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shortcuts: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.keyCode == UInt16(kVK_F7),
                  event.modifierFlags.intersection(shortcuts).isEmpty else { return event }
            return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
