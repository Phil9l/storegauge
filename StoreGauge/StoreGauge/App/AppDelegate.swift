//
//  AppDelegate.swift
//  StoreGauge
//
//  Keeps the app alive when the last window closes so it can live in the menu bar.
//

#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
#endif
