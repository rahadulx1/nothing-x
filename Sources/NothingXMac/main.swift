// Nothing X Mac: control Nothing and CMF earbuds from the menu bar.
// A status item opens a popover with the SwiftUI panel; right-click shows the app menu.

import AppKit
import Combine
import NothingKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static let appName = "Nothing X Mac"

    private let controller = EarbudsController()
    private let settings = AppSettings()
    private let navigation = PanelNavigation()
    private var lowBattery: LowBatteryNotifier?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var lastClosedAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        LoginItem.enableOnFirstRun()

        let panel = PanelView()
            .environmentObject(controller)
            .environmentObject(settings)
            .environmentObject(navigation)
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = .preferredContentSize // popover follows the panel's height
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Earbud.templateImage(.disconnected)
            button.imagePosition = .imageLeading
            button.toolTip = Self.appName
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Keep the menu bar title and tooltip in sync with the buds.
        controller.$state.combineLatest(settings.$menuBarBattery, settings.$menuBarCase)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, mode, showCase in
                self?.updateStatusItem(state: state, mode: mode, showCase: showCase)
            }
            .store(in: &cancellables)

        lowBattery = LowBatteryNotifier(controller: controller, settings: settings)
        controller.start()

        #if DEBUG
        // NXM_FAKE_LOW_BATTERY=1: pretend low earbuds are connected, to test alerts.
        if ProcessInfo.processInfo.environment["NXM_FAKE_LOW_BATTERY"] != nil {
            controller.stop()
            controller.loadSample()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                var state = self.controller.state
                state.battery.left = BatteryLevel(level: 18, charging: false)
                state.battery.right = BatteryLevel(level: 9, charging: false)
                self.controller.setSampleState(state)
            }
        }
        #endif

        // Dev convenience: NXM_OPEN=1 opens the panel on launch.
        if ProcessInfo.processInfo.environment["NXM_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Close the RFCOMM channel properly, or the buds refuse the next connection.
        controller.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func updateStatusItem(state: DeviceState, mode: MenuBarBattery, showCase: Bool) {
        guard let button = statusItem?.button else { return }
        let look = Self.look(for: state)
        if look != shownLook {
            shownLook = look
            button.image = Earbud.templateImage(look)
        }
        let text = state.connected ? mode.text(for: state.battery) : nil
        // SF 12 medium with tabular digits, 4 pt after the glyph; tinted like the glyph.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let title = NSMutableAttributedString(string: text.map { "\u{2009}\($0)" } ?? "", attributes: [.font: font])
        // Case level after the buds' text, behind a small case symbol, when the buds report it.
        if text != nil, showCase, let level = state.battery.case?.level {
            title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            if let symbol = Self.caseSymbol(font: font) {
                let attachment = NSTextAttachment()
                attachment.image = symbol
                attachment.bounds = CGRect(x: 0, y: font.descender + 1.5, width: symbol.size.width, height: symbol.size.height)
                title.append(NSAttributedString(attachment: attachment))
                title.append(NSAttributedString(string: "\u{2009}", attributes: [.font: font]))
            } else {
                title.append(NSAttributedString(string: "Case ", attributes: [.font: font]))
            }
            title.append(NSAttributedString(string: "\(level)%", attributes: [.font: font]))
        }
        button.attributedTitle = title
        button.toolTip = state.connected ? "\(Self.appName) · \(state.name ?? "")" : Self.appName
    }

    private var shownLook: Earbud.Look?

    /// The earbuds case SF Symbol as a template image sized for the menu bar title.
    private static func caseSymbol(font: NSFont) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: Earbud.Part.chargingCase.symbol, accessibilityDescription: "Case")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// Menu bar glyph: low once any part (not charging) is at 20% or below.
    static func look(for state: DeviceState) -> Earbud.Look {
        guard state.connected else { return state.connecting != nil ? .connecting : .disconnected }
        let parts = [state.battery.left, state.battery.right, state.battery.stereo].compactMap { $0 }
        return parts.contains { !$0.charging && $0.level <= 20 } ? .low : .connected
    }

    // MARK: Popover

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(lastClosedAt) > 0.25 {
            // A click on the icon closes the transient popover first; don't reopen it.
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        controller.refreshBattery()
        controller.refreshPaired()
        navigation.page = .main
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosedAt = Date()
        navigation.page = .main
    }

    // MARK: Context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        login.isEnabled = LoginItem.isSupported
        menu.addItem(login)

        let batteryItem = NSMenuItem(title: "Battery in Menu Bar", action: nil, keyEquivalent: "")
        let batteryMenu = NSMenu()
        for mode in MenuBarBattery.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setMenuBarBattery(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.menuBarBattery == mode ? .on : .off
            batteryMenu.addItem(item)
        }
        batteryItem.submenu = batteryMenu
        menu.addItem(batteryItem)

        let caseItem = NSMenuItem(title: "Show Case Battery", action: #selector(toggleMenuBarCase), keyEquivalent: "")
        caseItem.target = self
        caseItem.state = settings.menuBarCase ? .on : .off
        caseItem.isEnabled = settings.menuBarBattery != .off
        caseItem.toolTip = "Show the case level next to the earbuds when it's known"
        batteryMenu.addItem(.separator())
        batteryMenu.addItem(caseItem)

        let alerts = NSMenuItem(title: "Low Battery Alerts", action: #selector(toggleLowBatteryAlerts), keyEquivalent: "")
        alerts.target = self
        alerts.state = settings.lowBatteryAlerts ? .on : .off
        alerts.toolTip = "Notify at 20% and 10% for each earbud and the case"
        menu.addItem(alerts)

        let accent = NSMenuItem(title: "Use System Accent Color", action: #selector(toggleSystemAccent), keyEquivalent: "")
        accent.target = self
        accent.state = settings.useSystemAccent ? .on : .off
        menu.addItem(accent)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(Self.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        // Attach temporarily so the menu drops down from the icon like a normal menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func toggleSystemAccent() {
        settings.useSystemAccent.toggle()
    }

    @objc private func toggleMenuBarCase() {
        settings.menuBarCase.toggle()
    }

    @objc private func toggleLowBatteryAlerts() {
        settings.lowBatteryAlerts.toggle()
    }

    @objc private func setMenuBarBattery(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = MenuBarBattery(rawValue: raw) {
            settings.menuBarBattery = mode
        }
    }
}

#if DEBUG
MainActor.assumeIsolated { DebugSnapshots.runIfRequested() }
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
