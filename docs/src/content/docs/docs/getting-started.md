---
title: Getting started
description: Install StoreGauge, connect an account, and choose the apps shown in your dashboard.
---

Download the latest Mac release, move StoreGauge to **Applications**, and launch it. StoreGauge requires macOS 15 or later. The iPhone client requires iOS 18 or later.

1. Open **Accounts** from the bottom of the sidebar.
2. Choose **+**, then select App Store Connect or Google Play.
3. Follow the setup links inside StoreGauge and choose **Test & Add**.
4. Keep the apps you want in the dashboard selected and pin frequent apps to the top.

The **Ready to connect** checklist validates the credential shape before StoreGauge contacts the provider. **Test & Add** then verifies live access and reports how many apps the credential can see. For Google Play, remember that creating a service account is not enough by itself: its `client_email` must also be invited in Play Console under **Users and permissions**.

:::note[Local from the first launch]
StoreGauge has no sign-in of its own. Store credentials go to the Mac or iPhone Keychain and imported product data stays in the local SwiftData store.
:::

The iPhone client follows the same local-first model with its own Keychain and
SwiftData store. It does not sync accounts or downloaded data with the Mac, so
connect each account separately on the devices where you want to use it.

## iPhone background alerts

Enable **Store activity notifications** in StoreGauge’s iPhone Settings to let StoreGauge ask
iOS for a short background check no earlier than hourly. Background checks fetch
only new reviews and release status; analytics, financial reports, screenshots,
and metadata history wait for a normal foreground sync.

iOS decides when the task actually runs. Checks may be delayed when StoreGauge is
rarely opened, Background App Refresh is disabled, or Low Power Mode is enabled.
StoreGauge has no notification server, so it cannot promise exact hourly or
immediate delivery.

## Choose a provider

- Follow [Connect App Store Connect](../app-store-connect/) for Apple API access and sales reports.
- Follow [Connect Google Play](../google-play/) for Play Console, statistics reports, and Android vitals.

You can connect multiple accounts from either provider. StoreGauge discovers their apps and keeps each store’s terminology where the underlying numbers differ.

## Demo mode

Demo mode is available for evaluation and App Review, even though it is not promoted on the product landing page.

Choose either store in **Add Account**, enter `test` in every visible field, then choose **Test & Add**. Optional fields may be blank or contain `test`.

StoreGauge creates two labeled demo apps with 90 days of deterministic metrics, subscriptions, income, releases, and multilingual reviews. Replying, editing, and review triage work locally. Sync refreshes the demo without calling Apple or Google.

## Build from source

1. Clone the repository and open `StoreGauge/StoreGauge.xcodeproj`.
2. Select **StoreGauge** for Mac or **StoreGaugeMobile** for iPhone.
3. Assign the same development team to the StoreGauge, StoreGaugeWidgets, and StoreGaugeMCP targets.
4. Run with **Product → Run**.

Widgets and MCP activity sharing use an App Group, so their targets must share the same signing team.
