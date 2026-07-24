---
title: Connect Google Play
description: Create a Google service account, enable the required APIs, and grant Play Console access.
---

Google requires a service account that is created in Google Cloud and invited into the relevant Play developer account.

## Configure Google Cloud

1. Enable the [Google Play Android Developer API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com).
2. Enable the [Google Play Developer Reporting API](https://console.cloud.google.com/apis/library/playdeveloperreporting.googleapis.com) in the same project.
3. Create a service account and download its JSON key.

## Grant Play Console access

1. Open **Users and permissions** inside the relevant Play developer account.
2. Invite the JSON file’s `client_email` as a new user.
3. Grant access to the relevant apps.
4. Grant Global **View app information (read-only)**.
5. Grant **Reply to reviews** if you want to respond through StoreGauge.

In StoreGauge, choose **Add Account → Google Play Console**, select or paste the complete JSON key, and choose **Test & Add**.

:::caution[Apps appear, but reporting still fails]
App listing and reporting use different APIs and permissions. Confirm both APIs are enabled and the service account has Global View app information—not only app-level access.
:::

## Add statistics and income reports

Open **Download reports → Statistics** in Play Console and copy the private Cloud Storage bucket ID beginning with `pubsite_prod_rev_`. Add it to the account in StoreGauge.

- Global **View app information** enables daily user installs and device updates.
- Global **View financial data** additionally enables estimated gross sales and finalized earnings.

The complete JSON key stays in Keychain. Statistics and financial files are parsed locally, and StoreGauge does not retain raw transaction rows.

## Reporting delays

Install and estimated-sales exports commonly trail by several days. Finalized monthly earnings usually appear after the month closes. Android vitals use Google’s reported freshness date automatically.
