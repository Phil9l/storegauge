import Foundation
import MCP

@main
struct StoreGaugeMCPMain {
    static func main() async {
        let dataSource = MCPDataSource()
        let activity = MCPActivityReporter()
        let server = Server(
            name: "storegauge",
            version: "1.1.0",
            title: "StoreGauge",
            instructions: "Read-only access to the App Store Connect and Google Play data exported by StoreGauge. Use list_apps before querying a specific app.",
            capabilities: .init(resources: .init(), tools: .init()),
            configuration: .strict
        )

        await server.withMethodHandler(ListTools.self) { _ in
            await activity.record("listed tools")
            return .init(tools: MCPToolCatalog.tools)
        }
        await server.withMethodHandler(CallTool.self) { request in
            await activity.record(request.name.replacingOccurrences(of: "_", with: " "))
            do {
                let arguments = request.arguments ?? [:]
                let value: Value
                switch request.name {
                case "portfolio_summary":
                    value = try await dataSource.portfolio(days: boundedDays(arguments["days"]))
                case "list_apps":
                    value = try await dataSource.apps(arguments: arguments)
                case "get_app_performance":
                    value = try await dataSource.performance(
                        appID: arguments["app_id"]?.stringValue,
                        days: boundedDays(arguments["days"])
                    )
                case "list_metrics":
                    value = try await dataSource.metrics(arguments: arguments)
                case "list_reviews":
                    value = try await dataSource.reviews(arguments: arguments)
                case "get_release_status":
                    value = try await dataSource.releases(appID: arguments["app_id"]?.stringValue)
                case "list_release_history":
                    value = try await dataSource.releaseHistory(arguments: arguments)
                case "list_metadata":
                    value = try await dataSource.metadata(arguments: arguments)
                case "list_metadata_changes":
                    value = try await dataSource.metadataChanges(arguments: arguments)
                case "list_annotations":
                    value = try await dataSource.annotations(arguments: arguments)
                default:
                    throw MCPError.methodNotFound("Unknown StoreGauge tool: \(request.name)")
                }
                return result(value)
            } catch {
                return .init(content: [.text(error.localizedDescription)], isError: true)
            }
        }
        await server.withMethodHandler(ListResources.self) { _ in
            await activity.record("listed resources")
            return try await .init(resources: dataSource.resources())
        }
        await server.withMethodHandler(ReadResource.self) { request in
            await activity.record("read resource")
            let value = try await dataSource.resource(uri: request.uri)
            return .init(contents: [.text(json(value), uri: request.uri, mimeType: "application/json")])
        }

        let heartbeat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await activity.heartbeat()
            }
        }

        do {
            try await server.start(transport: StdioTransport()) { client, _ in
                await activity.connected(to: client.title ?? client.name)
            }
            await server.waitUntilCompleted()
            heartbeat.cancel()
            await heartbeat.value
            await activity.disconnected()
        } catch {
            heartbeat.cancel()
            await heartbeat.value
            await activity.failed(error.localizedDescription)
            writeError("StoreGauge MCP: \(error.localizedDescription)\n")
        }
    }
}

private enum MCPToolCatalog {
    static let tools: [Tool] = [
        Tool(
            name: "portfolio_summary",
            title: "Portfolio summary",
            description: "Summarize downloads, engagement, proceeds, reviews, and rating across exported apps.",
            inputSchema: objectSchema(["days": integerProperty("Number of recent days, 1–36500", default: 30)]),
            annotations: readOnly
        ),
        Tool(
            name: "list_apps",
            title: "List apps",
            description: "List exported App Store and Google Play apps with their IDs and release states.",
            inputSchema: objectSchema([
                "platform": stringProperty("Optional platform: apple-app-store or google-play"),
                "account": stringProperty("Optional exact account ID or account name"),
                "query": stringProperty("Optional case-insensitive name, bundle ID, SKU, or store ID search")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "get_app_performance",
            title: "App performance",
            description: "Convenience view of recent daily metrics for one app or the portfolio. Use list_metrics for complete, paginated history.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional StoreGauge ID, store ID, bundle ID, or exact app name"),
                "days": integerProperty("Number of recent days, 1–36500", default: 30)
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "list_metrics",
            title: "List metrics",
            description: "Query complete daily metric history with filters and cursor pagination.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name"),
                "platform": stringProperty("Optional platform: apple-app-store or google-play"),
                "kinds": stringArrayProperty("Optional metric kinds, such as installs, units, updates, proceeds, sessions, crashes, crashRate, or anrRate"),
                "source": stringProperty("Optional source, such as sales or analytics"),
                "start_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "end_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "limit": integerProperty("Maximum results, 1–1000", default: 200),
                "cursor": stringProperty("Opaque next_cursor from the previous response")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "list_reviews",
            title: "List reviews",
            description: "Query complete review history by app, triage state, rating, text, language, territory, response state, or date. Review text depends on StoreGauge privacy settings.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name"),
                "status": stringProperty("Optional triage status: needsReply, acknowledged, or answered"),
                "minimum_rating": integerProperty("Minimum star rating", default: 1),
                "maximum_rating": integerProperty("Maximum star rating", default: 5),
                "query": stringProperty("Optional case-insensitive text search"),
                "platform": stringProperty("Optional platform: apple-app-store or google-play"),
                "language": stringProperty("Optional reviewer language code"),
                "territory": stringProperty("Optional storefront territory code"),
                "has_response": booleanProperty("Optional response-presence filter"),
                "start_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "end_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "limit": integerProperty("Maximum results, 1–200", default: 50),
                "cursor": stringProperty("Opaque next_cursor from the previous response")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "get_release_status",
            title: "Release status",
            description: "Return current version and release state for one app or every exported app.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "list_release_history",
            title: "List release history",
            description: "Query recorded release-state changes with filters and cursor pagination.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name"),
                "platform": stringProperty("Optional platform: apple-app-store or google-play"),
                "state": stringProperty("Optional raw from/to release state"),
                "start_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "end_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "limit": integerProperty("Maximum results, 1–500", default: 100),
                "cursor": stringProperty("Opaque next_cursor from the previous response")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "list_metadata",
            title: "List app metadata",
            description: "Query current localized store-listing metadata with cursor pagination.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name"),
                "platform": stringProperty("Optional platform: apple-app-store or google-play"),
                "locale": stringProperty("Optional locale code"),
                "query": stringProperty("Optional case-insensitive search across listing text"),
                "limit": integerProperty("Maximum results, 1–200", default: 50),
                "cursor": stringProperty("Opaque next_cursor from the previous response")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "list_metadata_changes",
            title: "List metadata changes",
            description: "Query complete localized store-listing change history with cursor pagination.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name"),
                "platform": stringProperty("Optional platform: apple-app-store or google-play"),
                "locale": stringProperty("Optional locale code"),
                "field": stringProperty("Optional metadata field, such as name, subtitle, description, keywords, whatsNew, or screenshots"),
                "query": stringProperty("Optional case-insensitive old/new value search"),
                "start_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "end_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "limit": integerProperty("Maximum results, 1–500", default: 100),
                "cursor": stringProperty("Opaque next_cursor from the previous response")
            ]),
            annotations: readOnly
        ),
        Tool(
            name: "list_annotations",
            title: "List chart annotations",
            description: "Query app-specific and portfolio-wide chart notes with cursor pagination.",
            inputSchema: objectSchema([
                "app_id": stringProperty("Optional app identifier or exact name; omit to include global notes"),
                "category": stringProperty("Optional category: marketing, bugfix, release, experiment, or note"),
                "query": stringProperty("Optional case-insensitive note search"),
                "start_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "end_date": stringProperty("Optional inclusive ISO 8601 date or timestamp"),
                "limit": integerProperty("Maximum results, 1–500", default: 100),
                "cursor": stringProperty("Opaque next_cursor from the previous response")
            ]),
            annotations: readOnly
        )
    ]

    private static let readOnly = Tool.Annotations(
        readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false
    )
}

private func objectSchema(_ properties: [String: Value]) -> Value {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "additionalProperties": .bool(false)
    ])
}

private func stringProperty(_ description: String) -> Value {
    .object(["type": .string("string"), "description": .string(description)])
}

private func integerProperty(_ description: String, default defaultValue: Int) -> Value {
    .object([
        "type": .string("integer"), "description": .string(description),
        "default": .int(defaultValue)
    ])
}

private func booleanProperty(_ description: String) -> Value {
    .object(["type": .string("boolean"), "description": .string(description)])
}

private func stringArrayProperty(_ description: String) -> Value {
    .object([
        "type": .string("array"),
        "description": .string(description),
        "items": .object(["type": .string("string")]),
        "uniqueItems": .bool(true)
    ])
}

private func boundedDays(_ value: Value?) -> Int {
    min(max(value?.intValue ?? 30, 1), 36_500)
}

private func result(_ value: Value) -> CallTool.Result {
    .init(content: [.text(json(value))], structuredContent: Optional.some(value))
}

private func json(_ value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "{}"
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
