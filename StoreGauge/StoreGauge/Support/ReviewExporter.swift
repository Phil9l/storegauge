//
//  ReviewExporter.swift
//  StoreGauge
//
//  Exports reviews to CSV via a save panel.
//

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum ReviewExporter {
    static func csv(for reviews: [Review]) -> String {
        let df = ISO8601DateFormatter()
        var rows = ["App,Date,Rating,Title,Body,Reviewer,Territory,Status,Response,ResponseDate"]
        for r in reviews {
            let cols = [
                r.app?.name ?? "",
                df.string(from: r.createdDate),
                String(r.rating),
                r.title,
                r.body,
                r.reviewer,
                r.territory,
                r.triage.label,
                r.responseBody ?? "",
                r.responseDate.map { df.string(from: $0) } ?? "",
            ].map(escape)
            rows.append(cols.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    #if os(macOS)
    @MainActor
    static func exportPanel(_ reviews: [Review]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "reviews.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.title = "Export Reviews"
        if panel.runModal() == .OK, let url = panel.url {
            try? Data(csv(for: reviews).utf8).write(to: url)
        }
    }
    #endif
}
