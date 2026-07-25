# StoreGauge App Store listing

This is the reviewed source copy for App Store Connect. It deliberately omits
the private App Review contact email and phone number.

## Shared app information

- Name: `StoreGauge`
- Subtitle: `Reviews, revenue & releases`
- Primary category: Developer Tools
- Secondary category: Business
- Content rights: The app accesses third-party content and the developer has
  the necessary rights.
- Privacy policy: <https://phil9l.github.io/storegauge/privacy/>
- App privacy: No data collected by the developer.
- Copyright: `2026 Filipp Bazun`

## Keywords

`analytics,developer,dashboard,downloads,subscription,testflight,metadata,rankings,reply,google play`

## iPhone

### Promotional text

Track every app across App Store Connect and Google Play. Reviews, revenue,
releases, and performance stay private on your iPhone.

### Description

Your app-store business, one glance away.

StoreGauge brings App Store Connect and Google Play into one private, native
dashboard. It connects directly to the stores; there is no StoreGauge account,
backend, telemetry, or hosted database.

- Track downloads, proceeds, subscriptions, ratings, releases, and store health
- Triage, translate, reply to, and export customer reviews
- Compare apps and teams in readable charts
- Monitor production states, phased rollouts, TestFlight, crashes, and ANRs
- Receive local notifications for new reviews and release-state changes
- Keep private API keys in Keychain and imported data on your device

Explore the complete interface first with built-in demo data—no credentials or
network request required.

StoreGauge is for app developers and publishers. Real data requires API access
to App Store Connect, Google Play Console, or both. Background checks depend on
iOS scheduling and are best-effort.

### App Review notes

StoreGauge is a local developer dashboard for data belonging to the user’s own
App Store Connect or Google Play Console account. It never asks for an Apple ID
or password. Private API keys remain in the device Keychain, tokens are signed
locally, and requests go directly to Apple or Google. StoreGauge has no backend
or account system.

To review without credentials:

1. Launch StoreGauge.
2. On the welcome screen, tap “Explore with demo data.”

This creates two local demo apps with 90 days of representative metrics,
releases, subscriptions, income, and multilingual reviews. Review actions and
status changes work locally, and no network request or real credential is used.

Background App Refresh is best-effort and checks for new reviews and
release-state changes no earlier than hourly. It posts local notifications and
does not contact a StoreGauge server.

## macOS

### Promotional text

Track every app across App Store Connect and Google Play. Reviews, revenue,
releases, and performance stay private on your Mac.

### Description

Your app-store business, one glance away.

StoreGauge brings App Store Connect and Google Play into one private, native
dashboard. It connects directly to the stores; there is no StoreGauge account,
backend, telemetry, or hosted database.

- Track downloads, proceeds, subscriptions, ratings, releases, and store health
- Triage, translate, reply to, and export customer reviews
- Compare apps and teams in readable charts
- Monitor production states, phased rollouts, TestFlight, crashes, and ANRs
- Keep key metrics close with menu-bar status and widgets
- Optionally expose a local, read-only MCP integration to compatible assistants
- Keep private API keys in Keychain and imported data on your Mac

Explore the complete interface first with built-in demo data—no credentials or
network request required.

StoreGauge is for app developers and publishers. Real data requires API access
to App Store Connect, Google Play Console, or both. The Mac App Store build uses
App Store updates and does not include Sparkle.

### App Review notes

StoreGauge is a local developer dashboard for data belonging to the user’s own
App Store Connect or Google Play Console account. It never asks for an Apple ID
or password. Private API keys remain in the Mac Keychain, tokens are signed
locally, and requests go directly to Apple or Google. StoreGauge has no backend
or account system.

To review without credentials:

1. Launch StoreGauge and open Add Account.
2. Choose either store.
3. Enter `test` in every required visible field; optional fields may be blank
   or `test`.
4. Choose Test & Add.

This creates two local demo apps with 90 days of representative metrics,
releases, subscriptions, income, and multilingual reviews. Review actions and
status changes work locally, and no network request or real credential is used.

The Mac App Store build excludes Sparkle and uses App Store updates.

## Proposed commercial settings

- Universal one-time purchase: EUR 14.99
- Base country or region: Germany
- Availability: all countries and regions
- Distribution: public
- Release: manual after approval
- iPhone/iPad app on Apple silicon Mac: disabled because a native macOS version
  is supplied
- Apple Vision Pro compatibility listing: disabled
