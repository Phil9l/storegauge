//
//  StoreGaugeApp.swift
//  StoreGauge
//
//  App entry point. Declares the main window, the Settings scene and the menu-bar
//  extra, and builds the shared SwiftData container + AppModel.
//

import SwiftUI
import SwiftData
#if canImport(Sparkle) && !STOREGAUGE_APP_STORE
import Sparkle
#endif

@main
struct StoreGaugeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    private let container: ModelContainer
    #if canImport(Sparkle) && !STOREGAUGE_APP_STORE
    private let updaterController: SPUStandardUpdaterController
    #endif
    @State private var model: AppModel
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        #if canImport(Sparkle) && !STOREGAUGE_APP_STORE
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
        let container: ModelContainer
        do {
            let schema = Schema([Account.self, TrackedApp.self, Review.self, MetricPoint.self, StatusEvent.self,
                                 MetadataSnapshot.self, MetadataChange.self, ChartAnnotation.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        self.container = container
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        // A single dashboard window: reopening from the menu bar or the Dock brings
        // the existing one forward instead of stacking duplicates.
        Window("StoreGauge", id: "main") {
            RootView()
                .environment(model)
                .modelContainer(container)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .task { await model.bootstrap() }
                .onOpenURL { model.handleDeepLink($0) }
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            #if canImport(Sparkle) && !STOREGAUGE_APP_STORE
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
            #endif
            CommandGroup(after: .toolbar) {
                Button("Sync Now") { Task { await model.syncNow() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .modelContainer(container)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .frame(width: 760, height: 620)
        }

        #if os(macOS)
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environment(model)
                .modelContainer(container)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        } label: {
            MenuBarLabel(count: model.untriagedCount)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
struct MenuBarLabel: View {
    let count: Int

    private var countLabel: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        // Keep the brand mark visible in every state. Alerts append a compact
        // count instead of replacing StoreGauge with a generic bell symbol.
        HStack(spacing: 3) {
            // MenuBarExtra snapshots its label into a native status item. A
            // template image renders reliably there and automatically follows
            // the active menu-bar appearance and selection state.
            Image("StoreGaugeMenuIcon")
                .renderingMode(.template)

            if count > 0 {
                Text(countLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(count > 0 ? "StoreGauge, \(count) alerts" : "StoreGauge"))
    }
}
#endif
