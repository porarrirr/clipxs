import SwiftUI

struct TypeFilterBar: View {
    @Binding var selection: TypeFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TypeFilter.allCases) { filter in
                FilterChip(
                    title: NSLocalizedString(filter.titleKey, comment: ""),
                    isSelected: filter == selection
                ) {
                    selection = filter
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
