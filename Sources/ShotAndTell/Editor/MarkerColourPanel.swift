import AppKit

/// Shows the system colour picker and reports what's chosen, live.
///
/// SwiftUI's `ColorPicker` is the obvious thing to reach for, but inside a
/// `Menu` it renders disabled — you can see it and you can't use it. Driving
/// `NSColorPanel` directly is a dozen lines and gives the real Mac colour
/// picker, with its eyedropper, which is exactly the tool for "make the marks
/// something this screenshot isn't already full of".
@MainActor
final class MarkerColourPanel: NSObject {
    static let shared = MarkerColourPanel()

    private var onChange: ((NSColor) -> Void)?

    private override init() { super.init() }

    func show(initial: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colourChanged))
        panel.orderFront(nil)
    }

    @objc private func colourChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
