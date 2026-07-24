---
title: Roadmap
description: Planned directions for StoreGauge after the Apple and Google foundations.
---

StoreGauge is currently focused on making App Store Connect and Google Play reliable: clear sync health, direct distribution, guided onboarding, menu-bar workflows, widgets, and local MCP access.

## Future platform integrations

These are candidates rather than committed release dates:

- **Microsoft Store** — app acquisition, ratings and reviews, release state, and payout reporting where the APIs permit it.
- **Steam** — wishlists, traffic, sales, reviews, and release visibility for Steamworks partners.
- **Stripe** — subscription and payment context for apps whose revenue is not processed entirely by a mobile store.
- **Other storefronts** — considered when they provide stable APIs and enough cross-app value to justify ongoing maintenance.

New providers must remain local-first, avoid a StoreGauge cloud dependency, preserve provider-specific terminology, and expose normalized data through the same dashboard, widgets, exports, and MCP tools.

## iPhone client

The iPhone client is available in the source tree as the **StoreGaugeMobile**
scheme. It provides local dashboards, review triage and replies, release and
metadata visibility, notifications, themes, and account management using the
same store integrations as the Mac app.

It is deliberately independent rather than a synced companion: credentials stay
in the iPhone Keychain and downloaded data stays in that device’s SwiftData
store. Cross-device sync may be evaluated later only if it can preserve that
local-first privacy model.
