// Posts a macOS notification when the earbuds' battery runs low.
// Thresholds and "don't repeat" rules live in NothingKit's LowBatteryTracker.

import Combine
import Foundation
import NothingKit
import UserNotifications

final class LowBatteryNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var tracker = LowBatteryTracker()
    private var deviceName: String?
    private var authorizationRequested = false
    private var cancellables = Set<AnyCancellable>()

    /// UNUserNotificationCenter only works inside an app bundle; a bare
    /// `swift run` binary would crash on first use.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil

    init(controller: EarbudsController, settings: AppSettings) {
        super.init()
        center?.delegate = self

        controller.$state
            .map { ($0.connected, $0.name, $0.battery) }
            .removeDuplicates { $0 == $1 }
            .combineLatest(settings.$lowBatteryAlerts)
            .receive(on: RunLoop.main)
            .sink { [weak self] report, enabled in
                self?.handle(connected: report.0, name: report.1, battery: report.2, enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func handle(connected: Bool, name: String?, battery: Battery, enabled: Bool) {
        guard connected, let name else { return } // keep state across brief disconnects
        if name != deviceName {
            deviceName = name
            tracker.reset()
        }
        // Ask for permission the first time earbuds connect, not at app launch.
        if enabled { requestAuthorizationOnce() }

        let alerts = tracker.update(battery) // always run, so turning alerts on later doesn't fire stale ones
        guard enabled, !alerts.isEmpty else { return }
        post(alerts, device: name)
    }

    private func requestAuthorizationOnce() {
        guard let center, !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.info("Notification permission error: \(error.localizedDescription)") }
            Log.info("Notifications \(granted ? "allowed" : "not allowed")")
        }
    }

    private func post(_ alerts: [LowBatteryAlert], device: String) {
        let content = UNMutableNotificationContent()
        let critical = alerts.contains { $0.threshold <= 10 }
        content.title = critical ? "Battery Very Low" : "Low Battery"
        content.subtitle = device
        content.body = alerts
            .map { "\($0.part.label) \($0.level)%" }
            .joined(separator: " · ")
            + (critical ? ". Charge soon." : "")
        content.sound = .default

        Log.info("Low battery: \(content.body)")
        guard let center else { return }
        // One notification per device; a newer alert replaces the older one.
        let request = UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil)
        // Waits for the permission prompt on first use (returns at once after that),
        // so an alert that fires right as the buds connect isn't dropped.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request) { error in
                if let error { Log.info("Could not post notification: \(error.localizedDescription)") }
            }
        }
    }

    /// Show the banner even while the panel is open (the app counts as active then).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
