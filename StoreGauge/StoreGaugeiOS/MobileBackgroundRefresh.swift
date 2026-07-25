//
//  MobileBackgroundRefresh.swift
//  StoreGaugeMobile
//
//  Best-effort local background checks for reviews and release status.
//

import BackgroundTasks
import Foundation
import UIKit

@MainActor
enum MobileBackgroundRefresh {
    static let identifier = "com.bazun.storegauge.refresh"
    static let requestedInterval: TimeInterval = 60 * 60

    private static let lastCompletedKey = "mobileBackgroundRefreshLastCompletedAt"

    static var lastCompletedAt: Date? {
        UserDefaults.standard.object(forKey: lastCompletedKey) as? Date
    }

    static var availabilityLabel: String {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return "Paused by Low Power Mode"
        }
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            return "Available"
        case .denied:
            return "Off in iOS Settings"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unavailable"
        }
    }

    static func updateSchedule(enabled: Bool) {
        guard enabled, UIApplication.shared.backgroundRefreshStatus == .available else {
            cancel()
            return
        }
        schedule()
    }

    static func schedule() {
        // Keep exactly one pending request and move its earliest date forward
        // when settings or app lifecycle events reschedule the check.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: requestedInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            DiagnosticLog.record("iPhone · Could not schedule background refresh · \(error.localizedDescription)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    static func handle(model: AppModel) async {
        let enabled = model.settings.notificationsEnabled &&
            model.accounts().contains { !$0.isDemo }
        guard enabled else {
            cancel()
            return
        }

        // Submit the next request before starting work so a system expiration
        // does not break the recurring schedule.
        updateSchedule(enabled: true)
        DiagnosticLog.record("iPhone · Background alert refresh started")
        if await model.syncBackgroundAlerts() {
            UserDefaults.standard.set(Date(), forKey: lastCompletedKey)
            DiagnosticLog.record("iPhone · Background alert refresh completed")
        } else {
            DiagnosticLog.record("iPhone · Background alert refresh ended without a completed account")
        }
    }
}
