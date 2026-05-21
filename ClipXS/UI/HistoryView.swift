import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
            footer
        }
        .frame(width: 420, height: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(String(localized: "history_title"))
                .font(.headline)
            Spacer()
            Text(String(localized: "history_shortcut"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(String(localized: "history_empty"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        HistoryRowView(
                            entry: entry,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.paste(entry: entry)
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                guard viewModel.entries.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.entries[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(String(localized: "history_hint_navigate"), systemImage: "arrow.up.arrow.down")
            Label(String(localized: "history_hint_paste"), systemImage: "return")
            Label(String(localized: "history_hint_close"), systemImage: "escape")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04))
    }
}

struct HistoryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            typeIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .lineLimit(2)
                    .font(.system(size: 13))
                Text(typeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.type == .image, let image = NSImage(contentsOfFile: entry.payload) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
    }

    private var typeIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(width: 22)
    }

    private var iconName: String {
        switch entry.type {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }

    private var typeLabel: String {
        switch entry.type {
        case .text:
            return NSLocalizedString("type_text", comment: "")
        case .image:
            return NSLocalizedString("type_image", comment: "")
        case .files:
            return NSLocalizedString("type_files", comment: "")
        }
    }
}
