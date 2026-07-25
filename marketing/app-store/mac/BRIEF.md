# StoreGauge Mac App Store shots

## Goal

Create a consistent four-panel US-English Mac App Store story from genuine
StoreGauge windows populated with the app's local demo dataset.

## Story

1. **Hook — Overview**
   - Headline: **"See every store in one view"**
   - Source: `raw/01-overview.png`
   - Benefit: understand proceeds, downloads, devices, ratings, reviews, and
     release state at a glance.
2. **Core workflow — Reviews**
   - Headline: **"Turn reviews into momentum"**
   - Source: `raw/02-reviews.png`
   - Benefit: triage, reply to, and acknowledge feedback across apps.
3. **Business clarity — Income**
   - Headline: **"Understand every dollar"**
   - Source: `raw/03-income.png`
   - Benefit: follow proceeds, purchases, paid apps, refunds, apps, and
     territories.
4. **Growth — Subscriptions**
   - Headline: **"Track subscriber growth clearly"**
   - Source: `raw/04-subscriptions.png`
   - Benefit: monitor MRR, active subscribers, trials, renewals, and churn.

## Visual system

- Target: Mac App Store desktop screenshots, `2880 × 1800`.
- Locale: `en-US`.
- UI treatment: one authentic native StoreGauge window, floating without a
  laptop or monitor mockup.
- Headline: oversized bold modern grotesk on the left, exact quoted copy,
  high contrast, generous negative space.
- Background: matte near-black and deep ink, concentrated StoreGauge cobalt,
  subtle cool-cyan spectral light, fine film grain, and restrained
  spatial-glass planes.
- Composition: asymmetric landscape grid. The app window occupies the right
  two-thirds, is rotated no more than two degrees, and may crop slightly at the
  right or bottom edge while keeping the feature readable. At most two
  source-derived callouts float at the left.
- Avoid glossy hardware mockups, generic gradients, neon circuitry, decorative
  particles, and conventional centered software screenshots.

## Truthfulness constraints

- Use exactly one genuine StoreGauge capture per panel.
- Preserve source UI text, metrics, charts, icons, and controls.
- Floating elements may only repeat information visible in that panel.
- No Apple logo, third-party logo, watermark, fake metric, or invented
  functionality.

## Generation

Use `openai/gpt-image-2` through Avalava with the real source capture. Generate
wide and export to the exact `2880 × 1800` Mac App Store size.
