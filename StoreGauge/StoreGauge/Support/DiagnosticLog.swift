//
//  DiagnosticLog.swift
//  StoreGauge
//
//  Small, local-only rolling log for connector diagnostics. Callers must log
//  metadata only—never credentials, tokens, request/response bodies, or reviews.
//

import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
enum DiagnosticLog {
    private static let maximumBytes = 1_000_000
    private static let formatter = ISO8601DateFormatter()

    static var fileURL: URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("StoreGauge", isDirectory: true)
            .appendingPathComponent("StoreGauge.log", isDirectory: false)
    }

    static func record(_ message: String) {
        guard let fileURL else { return }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            try rotateIfNeeded(fileURL, manager: manager)
            if !manager.fileExists(atPath: fileURL.path) {
                _ = manager.createFile(atPath: fileURL.path, contents: nil)
            }
            let cleanMessage = message
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let line = "[\(formatter.string(from: Date()))] \(cleanMessage)\n"
            let handle = try FileHandle(forWritingTo: fileURL)
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            // Diagnostics must never interfere with sync or user actions.
        }
    }

    #if os(macOS)
    static func reveal() {
        record("Diagnostics · Log revealed from Settings")
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
    #endif

    private static func rotateIfNeeded(_ fileURL: URL, manager: FileManager) throws {
        let attributes = try? manager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size >= maximumBytes else { return }

        let previousURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("StoreGauge.previous.log", isDirectory: false)
        if manager.fileExists(atPath: previousURL.path) {
            try manager.removeItem(at: previousURL)
        }
        try manager.moveItem(at: fileURL, to: previousURL)
    }
}
