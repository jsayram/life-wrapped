//
//  CategorySelector.swift
//  LifeWrapped
//
//  Created on 2025-12-27.
//

import SwiftUI
import SharedModels

/// Segmented control for selecting work or personal recording category
struct CategorySelector: View {
    @Binding var category: SessionCategory
    let isDisabled: Bool
    
    init(category: Binding<SessionCategory>, isDisabled: Bool = false) {
        self._category = category
        self.isDisabled = isDisabled
    }
    
    var body: some View {
        Picker("Category", selection: $category) {
            ForEach(SessionCategory.allCases, id: \.self) { cat in
                Label {
                    Text(cat.displayName)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: cat.systemImage)
                }
                .tag(cat)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

#Preview("Category Selector") {
    VStack(spacing: 20) {
        CategorySelector(category: .constant(.work))
        CategorySelector(category: .constant(.personal))
        CategorySelector(category: .constant(.work), isDisabled: true)
    }
    .padding()
}
