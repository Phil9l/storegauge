//
//  ShortcutsOverlay.swift
//  StoreGauge
//
//  A HUD listing the current screen's keyboard shortcuts. It never takes over the
//  window on its own: holding ⌘ only lights up a hint in the status bar, and the
//  list itself opens on ⌘/ or from that status-bar button.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class KeyboardMonitor {
    /// The full HUD. Only ever shown on request (⌘/ or the status-bar button).
    private(set) var showOverlay = false
    /// A quiet nudge in the status bar while ⌘ is held down.
    private(set) var showHint = false
    /// Mirrors the "Hint at shortcuts while ⌘ is held" preference.
    var hintWhileCommandHeld = true {
        didSet { if !hintWhileCommandHeld { showHint = false } }
    }

    private var commandHeld = false {
        didSet { commandHeld ? scheduleHint() : (showHint = false) }
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

    func toggleOverlay() {
        showOverlay.toggle()
        showHint = false
    }

    func dismissOverlay() {
        showOverlay = false
    }

    /// Long enough that ordinary ⌘-shortcuts (⌘E, ⌘R…) never light the hint.
    private func scheduleHint() {
        guard hintWhileCommandHeld else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.commandHeld, self.hintWhileCommandHeld, !self.showOverlay else { return }
            self.showHint = true
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
    var dismiss: () -> Void = {}

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.14))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Keyboard Shortcuts", systemImage: "command").font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close (esc)")
                .accessibilityLabel("Close keyboard shortcuts")
            }
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
            Text("Press ⌘/ or esc to close.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }
}

/// Status-bar affordance: always available, and while ⌘ is held it expands into a
/// reminder that the full list is one keystroke away.
struct ShortcutsStatusButton: View {
    let isHinting: Bool
    let isShowingOverlay: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                // One label that swaps outright: crossfading two Texts in place
                // leaves them briefly overlapping and unreadable.
                Text(isHinting ? "Press ⌘/ for shortcuts" : "⌘/")
                    .monospaced(!isHinting)
                    .lineLimit(1)
                    .contentTransition(.identity)
            }
            .font(.caption)
            .foregroundStyle(isHinting || isShowingOverlay ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(.tint.opacity(isHinting ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("/", modifiers: .command)
        .help("Show keyboard shortcuts for this screen (⌘/)")
        .accessibilityLabel("Keyboard shortcuts")
    }
}
