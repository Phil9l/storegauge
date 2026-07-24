//
//  Poller.swift
//  StoreGauge
//
//  Fires a periodic refresh. The interval is read each cycle so preference
//  changes take effect on the next tick.
//

import Foundation

@MainActor
final class Poller {
    private var task: Task<Void, Never>?
    private let intervalMinutes: () -> Int
    private let action: () async -> Void

    init(intervalMinutes: @escaping () -> Int, action: @escaping () async -> Void) {
        self.intervalMinutes = intervalMinutes
        self.action = action
    }

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = max(5, self.intervalMinutes())
                try? await Task.sleep(for: .seconds(Double(minutes * 60)))
                if Task.isCancelled { break }
                await self.action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
