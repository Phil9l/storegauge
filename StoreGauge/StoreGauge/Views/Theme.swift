//
//  Theme.swift
//  StoreGauge
//
//  Colours, gradients and card styling shared across the UI.
//

import SwiftUI

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension StorePlatform {
    var color: Color {
        switch self {
        case .appleAppStore: return .primary
        case .googlePlay: return .blue
        }
    }

    var iconBackground: Color {
        switch self {
        case .appleAppStore: return .black
        case .googlePlay: return .blue
        }
    }
}

extension AppStoreState.Category {
    var color: Color {
        switch self {
        case .live: return .green
        case .inReview: return .orange
        case .pending: return .blue
        case .prepare: return .gray
        case .problem: return .red
        case .removed: return .brown
        case .other: return .secondary
        }
    }
}

extension AppStoreState {
    var color: Color { category.color }
}

extension TriageStatus {
    var color: Color {
        switch self {
        case .needsReply: return .orange
        case .acknowledged: return .secondary
        case .answered: return .green
        }
    }
}

extension MetricKind {
    var color: Color {
        switch self {
        case .proceeds: return .green
        case .units: return .blue
        case .updates: return .teal
        case .installs: return .indigo
        case .sessions: return .teal
        case .activeDevices: return .purple
        case .crashes: return .red
        case .crashRate: return .red
        case .anrRate: return .orange
        case .impressions: return .cyan
        case .pageViews: return .orange
        case .grossSales: return .mint
        case .netEarnings: return .green
        case .orders: return .blue
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color.opacity(0.55), color.opacity(0.04)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Distinct colours for per-app chart series and breakdown rows. Apps are coloured by
/// their position in the (name-sorted) app list so the colour of an app stays put while
/// charts, legends and the breakdown table are read side by side.
enum SeriesPalette {
    static let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal,
                                  .indigo, .mint, .cyan, .yellow, .brown, .red]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

extension Int {
    /// Colour for a 1–5 star rating.
    var ratingColor: Color {
        switch self {
        case 5: return .green
        case 4: return .mint
        case 3: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}

extension ShapeStyle where Self == Color {
    static var cardFill: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
    static var windowFill: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
}

// MARK: - Card styling

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 14) -> some View {
        modifier(CardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(title).font(.headline)
        }
    }
}
