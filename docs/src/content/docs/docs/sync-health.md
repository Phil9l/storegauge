---
title: Sync health
description: Understand StoreGauge data freshness, partial failures, retries, and diagnostic logs.
---

Open **Settings → Sync Health** to see every connected account in one place.

For each account, StoreGauge shows:

- whether its credential is available in macOS Keychain;
- the latest sync attempt and last completely successful sync;
- the newest locally stored product data;
- the duration and error from the latest attempt;
- Google Play freshness for Android vitals, install statistics, and financial reports; and
- whether optional Apple Sales reports or Google Play report buckets are configured.

Choose **Retry** for a normal account sync. Choose **Full Refresh** after changing store permissions or report access; it clears StoreGauge’s per-source refresh timers before syncing.

Temporary network failures, rate limits, and service outages are retried automatically with backoff. A failed optional source does not delete data imported successfully from another source.

## Diagnostic log

Choose **Reveal Log** to open StoreGauge’s metadata-only diagnostic log in Finder, or **Copy Log Path** when attaching it to a GitHub issue. The log never records credentials, access tokens, API response bodies, or review text.
