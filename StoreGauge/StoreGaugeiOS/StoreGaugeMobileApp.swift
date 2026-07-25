//
//  StoreGaugeMobileApp.swift
//  StoreGaugeMobile
//
//  Local-first iPhone entry point. The phone keeps its own SwiftData store and
//  Keychain credentials while reusing StoreGauge's provider and sync layers.
//

import SwiftData
import SwiftUI

@main
struct StoreGaugeMobileApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        // Ask from the Settings toggle after the user has seen why alerts are
        // useful instead of interrupting the first launch with a system prompt.
        UserDefaults.standard.register(defaults: ["notificationsEnabled": false])

        let schema = Schema([
            Account.self,
            TrackedApp.self,
            Review.self,
            MetricPoint.self,
            StatusEvent.self,
            MetadataSnapshot.self,
            MetadataChange.self,
            ChartAnnotation.self,
        ])

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
            self.container = container
            _model = State(initialValue: AppModel(container: container))
        } catch {
            fatalError("Could not create StoreGauge's local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(model)
                .modelContainer(container)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .task {
                    #if DEBUG
                    seedDemoForUITestingIfRequested()
                    #endif
                    await model.bootstrap()
                    MobileBackgroundRefresh.updateSchedule(
                        enabled: model.settings.notificationsEnabled &&
                            model.accounts().contains { !$0.isDemo }
                    )
                }
                .onOpenURL { model.handleDeepLink($0) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .background else { return }
                    MobileBackgroundRefresh.updateSchedule(
                        enabled: model.settings.notificationsEnabled &&
                            model.accounts().contains { !$0.isDemo }
                    )
                }
        }
        .backgroundTask(.appRefresh(MobileBackgroundRefresh.identifier)) {
            await MobileBackgroundRefresh.handle(model: model)
        }
    }

    #if DEBUG
    private func seedDemoForUITestingIfRequested() {
        guard ProcessInfo.processInfo.environment["STOREGAUGE_MOBILE_DEMO"] == "1",
              model.accounts().isEmpty else { return }
        let account = Account(
            name: "Demo · App Store",
            issuerID: Account.demoMarker,
            keyID: "DEMO",
            vendorNumber: "DEMO"
        )
        model.context.insert(account)
        try? model.context.save()
    }
    #endif
}
