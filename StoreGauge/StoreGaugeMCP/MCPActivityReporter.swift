import Foundation

actor MCPActivityReporter {
    private let sessionID = UUID().uuidString
    private var clientName: String?
    private var connectedAt: Date?
    private var lastActivityAt: Date?
    private var lastActivity: String?
    private var requestCount = 0

    func connected(to client: String) {
        clientName = client
        connectedAt = Date()
        save(state: .connected)
    }

    func record(_ activity: String) {
        lastActivity = activity
        lastActivityAt = Date()
        requestCount += 1
        save(state: .connected)
    }

    func heartbeat() {
        guard connectedAt != nil else { return }
        save(state: .connected)
    }

    func disconnected() {
        save(state: .disconnected)
    }

    func failed(_ message: String) {
        save(state: .error, error: message)
    }

    private func save(state: StoreGaugeMCPActivity.State, error: String? = nil) {
        let activity = StoreGaugeMCPActivity(
            state: state,
            sessionID: sessionID,
            clientName: clientName,
            connectedAt: connectedAt,
            lastHeartbeatAt: Date(),
            lastActivityAt: lastActivityAt,
            lastActivity: lastActivity,
            requestCount: requestCount,
            errorMessage: error
        )
        try? StoreGaugeMCPStorage.saveActivity(activity)
    }
}
