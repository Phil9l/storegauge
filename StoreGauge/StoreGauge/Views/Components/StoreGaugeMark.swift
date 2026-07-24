//
//  StoreGaugeMark.swift
//  StoreGauge
//
//  The full-color StoreGauge gauge used in welcome, About, and popover surfaces.
//  The menu-bar status item uses the separate monochrome template asset.
//

import SwiftUI

struct StoreGaugeMark: View {
    var body: some View {
        Image("StoreGaugeBrandMark")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Menu bar sizes") {
    HStack(spacing: 18) {
        StoreGaugeMark().frame(width: 16, height: 16)
        StoreGaugeMark().frame(width: 18, height: 18)
        StoreGaugeMark().frame(width: 44, height: 44)
    }
    .padding()
}
