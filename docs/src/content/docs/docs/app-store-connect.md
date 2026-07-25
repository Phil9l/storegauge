---
title: Connect App Store Connect
description: Create an Apple Team API key and add it to StoreGauge.
---

StoreGauge uses a Team API key to read App Store Connect and sign short-lived requests locally. The complete setup is also shown inside the Add Account sheet.

## Create the key

1. Open [Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Copy the **Issuer ID** shown above the keys table.
3. Create a Team API key and copy its **Key ID**.
4. Download the `.p8` private key. Apple allows it to be downloaded only once.
5. In StoreGauge, choose **Add Account → App Store Connect**, enter the values, and choose **Test & Add**.

Create a dedicated StoreGauge key and choose the lowest role that covers the features you need. Review replies require write access. Use the Admin role only if you want every StoreGauge feature; it has broad access. Individual keys cannot download Sales or Finance reports.

## Add sales and subscription reporting

Open [Payments and Financial Reports](https://appstoreconnect.apple.com/itc/payments_and_financial_reports#/) and copy the **Vendor Number** shown under your legal entity. Add it to the account in StoreGauge to enable proceeds, paid sales, refunds, subscriptions, MRR, and trial reporting.

| Credential | Stored in | Purpose |
| --- | --- | --- |
| Issuer ID and Key ID | Local SwiftData store | Identify the API key |
| `.p8` private key | Device Keychain | Sign short-lived requests |
| Vendor Number | Local SwiftData store | Download sales and subscription reports |

:::caution
Keep a secure backup of the `.p8` file. Apple does not allow the same private key to be downloaded again.
StoreGauge marks the imported Keychain item as device-only, so it does not migrate to another device through a backup.
:::

## What StoreGauge imports

Apple accounts can include reviews and replies, downloads and updates, proceeds, subscriptions, impressions, product-page views, conversion, sessions, active devices, release state, phased release progress, metadata history, TestFlight groups, tester counts, and crash feedback.
