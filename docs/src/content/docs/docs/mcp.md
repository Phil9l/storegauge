---
title: MCP for local agents
description: Configure StoreGauge's optional read-only MCP server for Codex, Claude, OpenCode, and other local clients.
---

StoreGauge bundles a native stdio [Model Context Protocol](https://modelcontextprotocol.io/) server. It lets Codex, Claude, [OpenCode](https://opencode.ai/docs/mcp-servers/), and other local MCP clients inspect a controlled snapshot of your portfolio.

## Enable sharing

1. Click the **MCP off** or **MCP ready** indicator at the bottom of StoreGauge.
2. Enable **Share StoreGauge data with local agents**.
3. Choose whether to include review text and reviewer names.
4. Choose whether to include proceeds, sales, and earnings.
5. Choose whether to include only apps selected for the dashboard.
6. Select Codex, Claude Code, Claude Desktop, or another MCP client for tailored setup.
7. Copy the configuration or install command, then restart or reconnect the client.

Example Codex configuration:

```toml
[mcp_servers.storegauge]
command = "/Applications/StoreGauge.app/Contents/MacOS/storegauge-mcp"
```

Example OpenCode configuration in `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "storegauge": {
      "type": "local",
      "command": [
        "/Applications/StoreGauge.app/Contents/MacOS/storegauge-mcp"
      ],
      "enabled": true
    }
  }
}
```

After changing the data scope, use **Refresh Data** or run a normal sync.

## Available tools

| Tool | What it returns |
| --- | --- |
| `portfolio_summary` | Downloads, engagement, financial fields, reviews, and rating across exported apps |
| `list_apps` | Exported Apple and Google apps, searchable by platform, name, bundle ID, SKU, or store ID |
| `get_app_performance` | Convenience view of recent daily metrics for one app or the portfolio |
| `list_metrics` | Complete metric history filtered by app, platform, kind, source, and date |
| `list_reviews` | Complete review history filtered by app, platform, triage state, rating, text, language, territory, response state, and date |
| `get_release_status` | Current version and release state for one or every exported app |
| `list_release_history` | Recorded release-state changes filtered by app, platform, state, and date |
| `list_metadata` | Current localized name, subtitle, description, keywords, URLs, What's New text, and screenshot fingerprint |
| `list_metadata_changes` | Complete localized listing-change history filtered by app, locale, field, text, and date |
| `list_annotations` | App-specific and portfolio-wide chart notes filtered by category, text, and date |

Every tool is declared read-only, non-destructive, and closed-world.

## Pagination

`list_metrics`, `list_reviews`, `list_release_history`, `list_metadata`, `list_metadata_changes`, and `list_annotations` use cursor pagination so an agent can safely query large histories without putting every record into one context window.

1. Call the tool with a `limit`.
2. Read `has_more` and `next_cursor` from the result.
3. If `has_more` is `true`, call the same tool again with the same filters and pass `next_cursor` as `cursor`.
4. Continue until `has_more` is `false`.

The cursor is opaque and tool-specific. Do not modify it or pass a review cursor to a metric query. Results are ordered newest first with stable identity tie-breakers, so newly imported records do not shift records between pages.

Every paginated response includes:

| Field | Meaning |
| --- | --- |
| `total_matches` | Number of exported records matching the filters, before applying the cursor |
| `page_size` | Number of records in this response |
| `has_more` | Whether another page is available |
| `next_cursor` | Cursor for the next page, or `null` on the final page |

Review and current-metadata pages default to 50 records and allow up to 200. Metric pages default to 200 and allow up to 1,000. Release-history, metadata-change, and annotation pages default to 100 and allow up to 500.

For example, an agent can request unanswered German-language reviews for one app:

```json
{
  "app_id": "com.example.app",
  "status": "needsReply",
  "language": "de",
  "start_date": "2026-01-01",
  "limit": 50
}
```

Or query only download and update metrics:

```json
{
  "platform": "apple-app-store",
  "kinds": ["units", "updates"],
  "start_date": "2025-01-01",
  "end_date": "2025-12-31",
  "limit": 500
}
```

Dates accept an ISO 8601 calendar date or timestamp and are inclusive. Use `list_apps` first when an app name is ambiguous.

## Security boundaries

The MCP helper reads a queryable JSON snapshot from StoreGauge’s App Group. Individual tool responses remain bounded through date filters and pagination. The helper does **not**:

- open Keychain;
- open the SwiftData product database;
- call Apple, Google, or another network service;
- modify StoreGauge data;
- export archived apps; or
- run unless sharing has been explicitly enabled.

The snapshot contains the complete locally stored metric, review, release-state, listing-metadata, metadata-change, and chart-annotation history for each exported app, plus portfolio-wide chart annotations. Non-secret account IDs and labels are included so agents can distinguish apps from different accounts. Financial fields and review text can be excluded independently. If **Only include apps selected for the dashboard** is enabled, unselected apps are not exported and therefore cannot be queried.

## Activity

While a client is active, the StoreGauge status shows the connected agent and latest request. Multiple concurrent clients are tracked separately. Click the indicator to see exported app count, connected client names, and recent activity.
