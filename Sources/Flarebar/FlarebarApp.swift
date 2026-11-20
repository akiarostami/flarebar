import AppKit
import Observation
import FlarebarCore
import SwiftUI

@main
struct FlarebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item, popover and settings window are managed by AppDelegate;
        // an App needs a scene, and this one shows nothing.
        Settings { EmptyView() }
    }
}

/// Owns the menu bar item, the menu panel that drops from it, and the settings window.
/// One system-wide shortcut slot is used, for opening the menu.
///
/// These are AppKit objects rather than a SwiftUI MenuBarExtra so that the menu opens
/// reliably (while the settings window is open, and after a change of Space) and can have
/// its own look.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var menu: MenuPanelController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A fixed name, set once. macOS files the item's position under this name, and menu bar
        // managers identify the item by the name they can see, which comes from the icon's
        // accessibility description ("Flarebar"). Left at the default ("Item-0") the two differ,
        // and a manager's request to move the item is filed under a name macOS does not know.
        statusItem.autosaveName = "Flarebar"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        model.openSettings = { [weak self] pane in
            self?.model.settingsPane = pane
            self?.showSettings()
        }
        menu = MenuPanelController(content: PopoverView().environment(model))

        // A menu left open in another Space would swallow the next click on the icon.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(closePopover), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        trackLabel()
        trackHotKeys()
        trackMenuContent()

        runSelfCheckIfAsked()

        // Arrow keys move through the popover's rows while it is open.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
    }

    /// For checking the interface, and taking its pictures, without looking at the screen:
    /// with FLAREBAR_SNAPSHOT_DIR set, the app opens its menu in several states and then each
    /// settings page, saving a PNG of each to that folder. Combine with FLAREBAR_DEMO for
    /// pictures that show invented data.
    private func runSelfCheckIfAsked() {
        guard let directory = ProcessInfo.processInfo.environment["FLAREBAR_SNAPSHOT_DIR"] else { return }
        let account = model.config.accounts.first
        let project = account.flatMap { a in a.projects.first.map { "\(a.id)/\($0.name)" } }
        let bill = account.map { "\($0.id)/#bill" }
        var steps: [(String, () -> Void)] = [
            ("menu", { [weak self] in
                self?.model.expanded = []
                self?.togglePopover()
            }),
            ("menu-usage", { [weak self] in
                if let project { self?.model.expanded = [project] }
            }),
            ("menu-deployments", { [weak self] in
                if let project { self?.model.deploymentRows = [project] }
            }),
            ("menu-bill", { [weak self] in
                self?.model.deploymentRows = []
                self?.model.expanded = bill.map { [$0] } ?? []
            }),
            ("settings-general", { [weak self] in
                self?.model.expanded = []
                self?.model.openSettings(.general)
            }),
            ("settings-accounts", { [weak self] in self?.model.openSettings(.accounts) }),
        ]
        if let account {
            steps.append(("settings-account", { [weak self] in self?.model.openSettings(.account(account.id)) }))
        }
        steps.append(("settings-about", { [weak self] in self?.model.openSettings(.about) }))
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5 + Double(index) * 4) { [weak self] in
                step.1()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    guard let self else { return }
                    let view = step.0.hasPrefix("menu") ? self.menu.contentView : self.settingsWindow?.contentView
                    DebugLog.snapshot(view, to: "\(directory)/\(step.0).png")
                }
            }
        }
    }

    /// Returns true when the key was used for the popover.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard menu.isShown, event.window === menu.window else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            switch event.keyCode {
            case 43: model.openSettings(model.settingsPane)  // Command-comma
            case 123: model.navigate(.usageTab)              // Command-Left
            case 124: model.navigate(.deploymentsTab)        // Command-Right
            case 12: NSApp.terminate(nil)                    // Command-Q
            default: return false
            }
            return true
        }
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 125: model.navigate(.down)
        case 126: model.navigate(.up)
        case 123: model.navigate(.left)
        case 124: model.navigate(.right)
        case 36, 76, 49: model.navigate(.toggle)  // Return, Enter, Space
        case 53: closePopover()                   // Esc
        default: return false
        }
        return true
    }

    /// Has the menu check its size whenever something it shows changes: rows opening or
    /// closing, new data, or errors.
    private func trackMenuContent() {
        withObservationTracking {
            _ = (model.expanded, model.deploymentRows, model.snapshots, model.errors,
                 model.config, model.tokens.count)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.trackMenuContent()
                // Once the change has been laid out, and again after its short animation.
                for delay in [0.0, 0.05, 0.25] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.menu.remeasure()
                    }
                }
            }
        }
    }

    // MARK: Shortcuts

    /// Registers the shortcut now and again whenever it changes.
    private func trackHotKeys() {
        let combo = withObservationTracking {
            model.hotKey
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackHotKeys() }
        }
        let registered = HotKeyCenter.shared.set(slot: 1, combo: combo) { [weak self] in
            self?.togglePopover()
        }
        model.hotKeyRefused = !registered
    }

    // MARK: Menu bar item

    /// Redraws the menu bar item now and again whenever the state it shows changes.
    private func trackLabel() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackLabel() }
        }
    }

    /// The cloud (a template image, coloured by the menu bar) with a small dot in the status
    /// colour on its top right corner.
    private func updateLabel() {
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarIcon

        if statusDot.superview == nil {
            button.addSubview(statusDot)
        }
        if let status = model.menuBarStatus {
            statusDot.layer?.backgroundColor = status.nsColour.cgColor
            statusDot.isHidden = false
        } else {
            statusDot.isHidden = true
        }
        positionDot()
        // The button is laid out again after its title changes; place the dot once more then.
        DispatchQueue.main.async { [weak self] in self?.positionDot() }
    }

    /// Puts the dot over the cloud's top right corner, so it adds no width to the item.
    /// The image's top edge is `cloudDrop` above the cloud itself, which puts the dot a
    /// little above the cloud's corner.
    private func positionDot() {
        guard let button = statusItem.button, let cell = button.cell as? NSButtonCell else { return }
        let image = cell.imageRect(forBounds: button.bounds)
        let size = Self.dotSize
        let x = image.maxX - size + 1
        let y = button.isFlipped ? image.minY - 1 : image.maxY - size + 1
        statusDot.frame = NSRect(x: x, y: y, width: size, height: size)
    }

    /// How far the cloud sits below the centre of the menu bar, in points.
    private static let cloudDrop: CGFloat = 1.5

    /// The mark with empty space above it, which lowers it in the menu bar.
    private static let menuBarIcon = BrandIcon.menuBarImage(width: 22, drop: cloudDrop)

    private static let dotSize: CGFloat = 7

    private let statusDot: NSView = {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: dotSize, height: dotSize))
        view.wantsLayer = true
        view.layer?.cornerRadius = dotSize / 2
        return view
    }()

    // MARK: Menu

    @objc private func togglePopover() {
        if menu.isShown {
            menu.close()
            return
        }
        // The click that opens the menu can also be the one that just closed it (the menu
        // closes as soon as it loses the keyboard); do not reopen it in that case.
        guard Date().timeIntervalSince(menu.lastClosed) > 0.25, let button = statusItem.button else { return }
        // The app is not activated: the menu is a panel that takes the keyboard by itself, so
        // the app you were in stays in front and gets its focus back when the menu closes.
        model.selectedRow = nil
        menu.show(below: button)
        Task { await model.refresh() }
    }

    @objc private func closePopover() {
        menu.close()
    }

    // MARK: Settings

    private func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(model)))
            window.title = "Flarebar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Rebuilt on next open, starting on General unless a page is asked for.
        settingsWindow = nil
        model.settingsPane = .general
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension Severity {
    var nsColour: NSColor {
        switch self {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }

    var colour: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    /// Bars stay in the accent colour until they need attention.
    var barColour: Color {
        self == .normal ? .accentColor : colour
    }
}
