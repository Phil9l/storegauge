---
title: Troubleshooting
description: Diagnose account permissions, missing reports, MCP connections, and signed updates.
---

## Open diagnostics

Open **Settings → Sync Health** to see the affected account, source freshness, retry controls, and the rolling connector log. Clicking a sync error in the status bar opens the same health view.

```text
~/Library/Logs/StoreGauge/StoreGauge.log
```

Logs contain operation names, HTTP status codes, and errors. They exclude credentials, access tokens, response bodies, and review text.

## Google returns a permissions error

Confirm both Google APIs are enabled, the service account was invited to the correct Play developer account, and it has Global **View app information** in addition to app-level access.

## Android vitals are unavailable

Transient 429 and 5xx responses retry with backoff. If the issue persists, confirm the Developer Reporting API is enabled and retry later. StoreGauge requests data only through Google’s current freshness boundary.

## Income is empty

- For Apple, add the Vendor Number to the account.
- For Google, add the `pubsite_prod_rev_` report bucket and grant Global **View financial data**.
- Reports may not exist yet for new accounts or recent dates.

## An MCP client cannot connect

1. Confirm MCP sharing is enabled in **Settings → Integrations**.
2. Confirm the configured executable path points inside the installed StoreGauge application.
3. Use **Refresh Data** after changing the export scope.
4. Restart or reconnect the MCP client after changing its configuration.
5. Click the MCP status indicator to inspect activity and the exported app count.

## An update check fails

Confirm you are online and using a direct-download build. App Store editions do not use Sparkle. If no public release exists yet, the feed can intentionally contain no update item.

Still stuck? [Open an issue](https://github.com/Phil9l/storegauge/issues/new) with your StoreGauge version, macOS version, store type, and sanitized diagnostic lines.
