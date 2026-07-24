import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://phil9l.github.io",
  base: "/storegauge",
  integrations: [
    sitemap(),
    starlight({
      title: "StoreGauge",
      description: "Private App Store Connect and Google Play analytics for macOS.",
      favicon: "/assets/storegauge.svg",
      disable404Route: true,
      customCss: ["./src/styles/starlight.css"],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/Phil9l/storegauge"
        }
      ],
      sidebar: [
        {
          label: "Start",
          items: [
            { label: "Overview", slug: "docs" },
            { label: "Getting started", slug: "docs/getting-started" }
          ]
        },
        {
          label: "Connect your stores",
          items: [
            { label: "App Store Connect", slug: "docs/app-store-connect" },
            { label: "Google Play", slug: "docs/google-play" }
          ]
        },
        {
          label: "Use StoreGauge",
          items: [
            { label: "Dashboard and apps", slug: "docs/dashboard" },
            { label: "Reviews", slug: "docs/reviews" },
            { label: "Sync health", slug: "docs/sync-health" },
            { label: "Widgets and menu bar", slug: "docs/widgets" },
            { label: "MCP for local agents", slug: "docs/mcp" }
          ]
        },
        {
          label: "Reference",
          items: [
            { label: "Privacy", link: "/privacy/" },
            { label: "Troubleshooting", slug: "docs/troubleshooting" },
            { label: "Direct distribution", slug: "docs/distribution" },
            { label: "Roadmap", slug: "docs/roadmap" }
          ]
        }
      ]
    })
  ]
});
