# StoreGauge Mac App Store generation prompts

Model: `openai/gpt-image-2`

Final export: `2880 × 1800`

The story and shared visual rules live in [`BRIEF.md`](BRIEF.md).

## Shared prompt

> Create a highly contemporary 2026 Mac App Store marketing panel for
> StoreGauge using the supplied genuine StoreGauge macOS window screenshot as
> the only source UI. Premium editorial technology campaign. Wide 16:10
> landscape composition. Match the approved StoreGauge system: matte near-black
> and deep ink canvas, a concentrated electric-cobalt field, subtle cool-cyan
> spectral light, fine film grain, restrained translucent spatial-glass planes,
> sophisticated asymmetric grid, and generous negative space. No laptop,
> monitor, keyboard, desk, Apple logo, hardware mockup, generic gradient, glossy
> floor, neon circuitry, cyberpunk, or decorative particles. Place one
> authentic native macOS app window across the right two-thirds, very large,
> floating with realistic soft depth, rotated no more than 1–2 degrees and
> allowed to crop slightly at the right or bottom edge while keeping the primary
> feature readable. Place the exact headline on the left in oversized clean
> bold modern grotesk sans-serif, carefully art-directed over two to four lines.
> Add at most two floating dimensional callouts near the left-middle, copied
> only from exact information visible in the supplied screenshot. Treat them as
> crisp translucent spatial layers, not white stickers. If exact source text
> cannot be preserved in a callout, use only exact source chart shapes or icons
> without text. CRITICAL SOURCE FIDELITY: preserve every visible pixel, word,
> number, chart, icon, color, sidebar item, and control inside the app window.
> Do not redraw, rewrite, translate, approximate, clean up, restyle, or invent
> any in-app UI. One app window only. No watermark, fake metric, fake
> notification, fake review, or misleading functionality.

## 01 — Overview

Panel prompt appended to the shared prompt:

> Headline: "See every store in one view". Feature emphasis: the Overview
> dashboard. Use the source Proceeds total and Downloads metric or chart as the
> two possible callouts. Keep the shared cobalt system with restrained emerald
> and cyan accents.

- Generation: `nhjbzufq2ykf4mkfu2qn`
- Cost: 20 credits
- Source: `raw/01-overview.png`
- Output: `en-US/01-overview.png`

## 02 — Reviews

The first shared-prompt generation, `o20js7ggq0j49mzim1e8`, was declined by
the provider before rendering. It cost 20 credits.

Successful retry prompt:

> Create a premium 2026 Mac App Store marketing screenshot. Use the supplied
> StoreGauge Reviews screenshot as the exact app window and preserve all of its
> visible content. Place that one native macOS window very large on the right
> over a matte near-black and electric-cobalt editorial background with subtle
> cool light and restrained translucent depth. Add the exact headline "Turn
> reviews into momentum" in large clean white type on the left. Add only a
> simple floating five-star strip and a small blue reply-button accent based on
> the supplied source. No people, no hardware, no Apple logo, no watermark, no
> invented app content, no extra app windows. Wide landscape composition.

- Generation: `n116101jviqlov3ozr84`
- Cost: 20 credits
- Source: `raw/02-reviews.png`
- Output: `en-US/02-reviews.png`

## 03 — Income

Panel prompt appended to the shared prompt:

> Headline: "Understand every dollar". Feature emphasis: the Income dashboard.
> Use the exact source Total Proceeds value and one source country or app
> bar-chart fragment as the two possible callouts. Keep the shared cobalt system
> with restrained emerald and cool-silver accents.

- Generation: `a69z4zwkne7x8jh3t73j`
- Cost: 20 credits
- Source: `raw/03-income.png`
- Output: `en-US/03-income.png`

## 04 — Subscriptions

The first shared-prompt generation, `ast4badxuoaxxent50lc`, was declined by
the provider before rendering. It cost 20 credits.

Successful retry prompt:

> Create a premium 2026 Mac App Store marketing screenshot. Use the supplied
> StoreGauge Subscriptions screenshot as the exact app window and preserve all
> of its visible content. Place that one native macOS window very large on the
> right over a matte near-black and electric-cobalt editorial background with
> subtle cool light and restrained translucent depth. Add the exact headline
> "Track subscriber growth clearly" in large clean white type on the left. Add
> only a simple floating MRR tile and a small coral subscriber-chart accent
> based on the supplied source. No people, no hardware, no Apple logo, no
> watermark, no invented app content, no extra app windows. Wide landscape
> composition.

- Generation: `o7g9z1ipjiil9hbr99ki`
- Cost: 20 credits
- Source: `raw/04-subscriptions.png`
- Output: `en-US/04-subscriptions.png`

## Export

Each accepted generation was proportionally scaled and top-cropped to Apple's
desktop screenshot aspect ratio. No UI was stretched.

- Directory: `store/appstore-desktop/`
- Dimensions: `2880 × 1800`
- Order: Overview, Reviews, Income, Subscriptions
- Total generation cost: 120 credits, including the two declined attempts
