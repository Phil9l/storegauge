//
//  ShortcutsOverlay.swift
//  StoreGauge
//
//  A HUD listing the current screen's keyboard shortcuts, shown while ⌘ is held.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class KeyboardMonitor {
    private(set) var showOverlay = false
    private var commandHeld = false {
        didSet { commandHeld ? scheduleShow() : (showOverlay = false) }
    }
    #if os(macOS)
    private var monitor: Any?
    private var resign: NSObjectProtocol?
    #endif

    func start() {
        #if os(macOS)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let cmd = event.modifierFlags.contains(.command)
            MainActor.assumeIsolated { self?.commandHeld = cmd }
            return event
        }
        // If the app loses focus while ⌘ is down we never see the key-up, so reset.
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.commandHeld = false }
        }
        #endif
    }

    /// Small delay so plain ⌘-shortcuts (⌘E, ⌘R…) don't flash the HUD.
    private func scheduleShow() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.commandHeld else { return }
            self.showOverlay = true
        }
    }
}

struct ShortcutHint: Identifiable {
    let id = UUID()
    let keys: String
    let action: String
}

struct ShortcutsOverlay: View {
    let shortcuts: [ShortcutHint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keyboard Shortcuts", systemImage: "command").font(.headline)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(shortcuts) { s in
                    HStack(spacing: 12) {
                        Text(s.keys)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                            .frame(minWidth: 62, alignment: .center)
                        Text(s.action).font(.callout)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .allowsHitTesting(false)
    }
}
