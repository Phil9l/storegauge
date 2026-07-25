# StoreGauge iPhone App Store shots

## Goal

Create a consistent three-panel US-English App Store story from genuine iPhone
simulator captures. StoreGauge is a local-first App Store Connect companion that
lets developers monitor stores, reviews, and release state without sending their
credentials or analytics to a third-party service.

## Story

1. **Hook — Overview**
   - Headline: **"See every store at a glance"**
   - Benefit: understand downloads, proceeds, review workload, and app status
     from one dashboard.
   - Source: `raw/overview.png`
2. **Core feature — Reviews**
   - Headline: **"Turn reviews into momentum"**
   - Benefit: find feedback that needs a reply and respond faster.
   - Source: `raw/reviews.png`
3. **Differentiator — Apps**
   - Headline: **"Track every release with confidence"**
   - Benefit: see store readiness and review state without opening App Store
     Connect.
   - Source: `raw/apps.png`

## Visual system

- Target: iPhone App Store, 6.9-inch portrait, `1320 × 2868`.
- Locale: `en-US`.
- Device: a refined black iPhone frame matching the source capture.
- Headline: oversized bold modern grotesk in the upper-left; exact quoted copy;
  high contrast; generous negative space.
- Background: matte near-black and deep ink, concentrated StoreGauge cobalt,
  subtle cool-cyan spectral light, fine film grain, restrained spatial-glass
  planes, and feature-specific violet, amber, emerald, or silver accents.
- Composition: a sophisticated asymmetric grid. The device is very large,
  rotated 3–5 degrees, and emerges diagonally from the lower-right with
  intentional edge cropping. At most two UI-derived spatial callouts float near
  the left edge.
- Consistency: identical device angle, headline placement, type treatment,
  background formula, lighting, and margins across all panels.

## Truthfulness constraints

- Use exactly one genuine screenshot as the phone screen for each panel.
- Preserve every source UI pixel, word, number, chart, icon, and control.
- Never redraw, translate, invent, or remove in-app content.
- Floating elements may only repeat information already visible in that panel's
  source screenshot.
- No Apple logo, third-party logo, watermark, fake notification, fake rating, or
  implied functionality.

## Generation model

`openai/gpt-image-2` through Avalava, with one source screenshot and a `9:16`
generation per panel. Export by resizing to the exact 6.9-inch App Store size;
do not crop the generated composition.
