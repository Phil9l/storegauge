//
//  CSVExporter.swift
//  StoreGauge
//
//  Generic CSV building + save-panel export.
//

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum CSVExporter {
    static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func row(_ cols: [String]) -> String { cols.map(escape).joined(separator: ",") }

    #if os(macOS)
    @MainActor
    static func save(_ csv: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.title = "Export CSV"
        if panel.runModal() == .OK, let url = panel.url {
            try? Data(csv.utf8).write(to: url)
        }
    }
    #endif
}
