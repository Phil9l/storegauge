//
//  Notifier.swift
//  StoreGauge
//
//  Local notifications for new reviews, status changes and newly discovered apps.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .notDetermined: return "Not requested"
        case .denied: return "Disabled in Settings"
        case .authorized: return "Allowed"
        case .provisional: return "Delivered quietly"
        case .ephemeral: return "Temporarily allowed"
        @unknown default: return "Unknown"
        }
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorizationStatus = .denied
        }
        await refreshAuthorizationStatus()
        return isAuthorized
    }

    func notify(title: String, body: String, id: String = UUID().uuidString) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyNewReview(app: String, rating: Int, title: String, body: String) {
        let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
        let snippet = title.isEmpty ? String(body.prefix(80)) : title
        notify(title: "New review · \(app)", body: "\(stars)  \(snippet)")
    }

    func notifyStatusChange(app: String, state: AppStoreState) {
        notify(title: "\(app) → \(state.label)", body: "App status changed.")
    }

    func notifyNewApp(app: String) {
        notify(title: "New app discovered", body: app)
    }

    func notifyAnomaly(app: String, metric: String, fraction: Double, from: String, to: String) {
        let up = fraction >= 0
        let pct = Format.percentPlain(abs(fraction))
        notify(title: "\(app): \(metric) \(up ? "▲" : "▼") \(pct)",
               body: "\(metric) \(up ? "up" : "down") \(pct) this week vs last (\(from) → \(to)).",
               id: "anomaly-\(app)-\(metric)")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
