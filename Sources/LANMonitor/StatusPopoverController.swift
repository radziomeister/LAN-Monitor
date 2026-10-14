import Cocoa
import SwiftUI

/// Shows the live status dropdown as an NSPopover anchored to the status bar button,
/// instead of a separate window — the standard "menu bar dashboard" pattern.
final class StatusPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let state: MonitorState
    private weak var statusItem: NSStatusItem?

    var onOpenLog: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRedetect: (() -> Void)?
    var onQuit: (() -> Void)?
    var onStartSpeedTest: (() -> Void)?
    var onCancelSpeedTest: (() -> Void)?

    init(statusItem: NSStatusItem, state: MonitorState) {
        self.statusItem = statusItem
        self.state = state
        super.init()
        popover.behavior = .transient
        popover.delegate = self

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggle)
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.close()
            return
        }
        let view = StatusDropdownView(
            onOpenLog: { [weak self] in self?.onOpenLog?(); self?.popover.close() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?(); self?.popover.close() },
            onRedetect: { [weak self] in self?.onRedetect?() },
            onQuit: { [weak self] in self?.onQuit?() },
            onStartSpeedTest: { [weak self] in self?.onStartSpeedTest?() },
            onCancelSpeedTest: { [weak self] in self?.onCancelSpeedTest?() }
        )
        .environmentObject(state)

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        if let button = statusItem?.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
