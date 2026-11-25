// Small timer helpers plus a setting change that isn't final until the earbuds confirm it.

import Foundation

/// A cancellable, reschedulable one-shot timer on the main queue.
final class Delayed {
    private var work: DispatchWorkItem?

    func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: block)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}

/// A group of one-shot timers that can all be cancelled at once (e.g. on disconnect).
final class TimerBag {
    private var items: [DispatchWorkItem] = []

    func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        items.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelAll() {
        items.forEach { $0.cancel() }
        items.removeAll()
    }
}

/// After a change is sent, the earbuds may keep reporting the old value for a
/// moment. While a change is pending, reports that don't match the target are
/// ignored and the value is read again shortly. If no confirmation arrives in
/// time, the pending state is dropped and the next report is trusted.
final class ConfirmedSetting<Value> {
    private static var firstRead: TimeInterval { 0.4 }
    private static var retry: TimeInterval { 0.5 }
    private static var timeout: TimeInterval { 4 }

    private let read: () -> Void
    private let matches: (Value, Value) -> Bool
    private let onTimeout: () -> Void
    private let readTimer = Delayed()
    private let timeoutTimer = Delayed()
    private(set) var target: Value?

    var pending: Bool { target != nil }

    init(read: @escaping () -> Void,
         matches: @escaping (Value, Value) -> Bool,
         onTimeout: @escaping () -> Void) {
        self.read = read
        self.matches = matches
        self.onTimeout = onTimeout
    }

    func begin(_ value: Value) {
        target = value
        readTimer.schedule(Self.firstRead, read)
        timeoutTimer.schedule(Self.timeout) { [weak self] in
            guard let self, self.pending else { return }
            self.reset()
            self.onTimeout()
            self.read() // show whatever the earbuds settled on
        }
    }

    /// Returns true if the report should be applied to state.
    func accept(_ report: Value) -> Bool {
        guard let target else { return true }
        if matches(report, target) {
            reset()
            return true
        }
        readTimer.schedule(Self.retry, read) // still switching; ask again shortly
        return false
    }

    func reset() {
        target = nil
        readTimer.cancel()
        timeoutTimer.cancel()
    }
}

extension ConfirmedSetting where Value: Equatable {
    convenience init(read: @escaping () -> Void, onTimeout: @escaping () -> Void) {
        self.init(read: read, matches: ==, onTimeout: onTimeout)
    }
}
