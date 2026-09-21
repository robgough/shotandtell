import AppKit
import Combine
import SwiftUI

/// The "click, then press the keys you want" control.
///
/// A local event monitor rather than a first-responder view, because while it's
/// recording it has to see keystrokes that would otherwise be eaten by menu key
/// equivalents — ⌘W would close the Settings window instead of being recorded.
struct HotkeyRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Text(label)
                        .frame(minWidth: 120)
                        .monospacedDigit()
                }
                .buttonStyle(.bordered)

                if combo != nil, !isRecording {
                    Button("Clear") {
                        combo = nil
                        problem = nil
                    }
                    .buttonStyle(.link)
                }
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
        // onDisappear is not enough. The Settings window is a shared controller
        // with isReleasedWhenClosed false, so closing it orders the window out
        // without tearing down the hosting view — leaving a local key monitor
        // installed application-wide. It would then swallow plain keystrokes
        // everywhere, and the next ⌘-combination typed anywhere in the app
        // would silently become the global shortcut.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stop()
        }
    }

    private var label: String {
        if isRecording { return "Press keys…" }
        return combo?.displayString ?? "Click to set"
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        problem = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }

            // 53 is Escape: abandon recording and keep whatever was there.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            // 51 is Delete: clear the shortcut entirely.
            if event.keyCode == 51 {
                combo = nil
                stop()
                return nil
            }

            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
            guard candidate.isUsable else {
                problem = "Use at least one of ⌘, ⌃ or ⌥ — otherwise it would fire while you type."
                return nil
            }

            combo = candidate
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
