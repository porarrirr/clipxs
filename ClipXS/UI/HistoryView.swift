import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject private var pasteQueue = PasteQueue.shared

    static let panelSize = CGSize(width: 720, height: 480)
    private static let listWidth: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            TypeFilterBar(selection: $viewModel.typeFilter)
            if !pasteQueue.entries.isEmpty {
                queueBar
            }
            Divider()
            content
            if !viewModel.multiSelectedIds.isEmpty {
                Divider()
                multiSelectionBar
            }
            Divider()
            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            SearchField(
                text: $viewModel.searchText,
                placeholder: NSLocalizedString("search_placeholder", comment: "")
            )
            Text(HotkeyFormatter.displayString(
                keyCode: SettingsAccess.hotkeyKeyCode,
                carbonModifiers: SettingsAccess.hotkeyModifiers
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var queueBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.number")
                .font(.system(size: 11))
            Text(String(format: NSLocalizedString("queue_bar_count", comment: ""), pasteQueue.entries.count))
            Text(String(
                format: NSLocalizedString("queue_bar_hint", comment: ""),
                HotkeyFormatter.displayString(
                    keyCode: SettingsAccess.hotkeyKeyCode,
                    carbonModifiers: SettingsAccess.queueHotkeyModifiers
                )
            ))
            .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "queue_clear")) {
                pasteQueue.clear()
            }
            .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.08))
    }

    private var multiSelectionBar: some View {
        HStack(spacing: 8) {
            Text(String(format: NSLocalizedString("multi_select_count", comment: ""), viewModel.multiSelectedIds.count))
            Spacer()
            Button(String(localized: "multi_merge_paste")) {
                viewModel.pasteMergedSelection()
            }
            .controlSize(.small)
            .disabled(viewModel.mergeableSelectionCount < 2)
            Button(String(localized: "context_add_to_queue")) {
                viewModel.enqueueSelection()
            }
            .controlSize(.small)
            Button(String(localized: "multi_clear")) {
                viewModel.clearMultiSelection()
            }
            .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var content: some View {
        let visible = viewModel.visibleEntries
        if visible.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                entryList(visible)
                    .id(viewModel.presentationID)
                    .frame(width: Self.listWidth)
                Divider()
                PreviewPane(viewModel: viewModel)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.allEntries.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(String(localized: viewModel.allEntries.isEmpty ? "history_empty" : "history_no_results"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryList(_ visible: [ClipboardEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        HistoryRowView(
                            entry: entry,
                            isSelected: index == viewModel.selectedIndex,
                            isMultiSelected: viewModel.multiSelectedIds.contains(entry.id),
                            index: index
                        )
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // ⌘クリックは複数選択のトグル、通常クリックは即貼り付け。
                            if NSEvent.modifierFlags.contains(.command) {
                                viewModel.toggleMultiSelection(entry: entry)
                                viewModel.selectedIndex = index
                            } else {
                                viewModel.selectedIndex = index
                                viewModel.paste(entry: entry)
                            }
                        }
                        .contextMenu {
                            contextMenu(for: entry)
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                guard visible.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(visible[newIndex].id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: ClipboardEntry) -> some View {
        Button(String(localized: "context_paste")) {
            viewModel.paste(entry: entry)
        }
        if !entry.fileURLs.isEmpty {
            Button(String(localized: "context_paste_paths")) {
                viewModel.pasteFilePaths(entry: entry)
            }
        }
        if entry.richFormat != nil {
            Button(String(localized: "context_paste_plain")) {
                viewModel.paste(entry: entry, plainTextOnly: true)
            }
        }
        if entry.type == .text {
            Menu(String(localized: "context_transform")) {
                ForEach(TextTransform.allCases) { transform in
                    Button(String(localized: String.LocalizationValue(transform.titleKey))) {
                        viewModel.pasteTransformed(entry: entry, transform: transform)
                    }
                }
            }
        }
        if entry.type == .image, let ocrText = entry.ocrText, !ocrText.isEmpty {
            Button(String(localized: "context_paste_ocr")) {
                viewModel.pasteOCRText(entry: entry)
            }
            Button(String(localized: "context_copy_ocr")) {
                viewModel.copyOCRText(entry: entry)
            }
        }
        Button(String(localized: "context_copy")) {
            viewModel.copyOnly(entry: entry)
        }
        Divider()
        if viewModel.multiSelectedIds.count > 1, viewModel.multiSelectedIds.contains(entry.id) {
            Button(String(format: NSLocalizedString("context_merge_paste", comment: ""), viewModel.multiSelectedIds.count)) {
                viewModel.pasteMergedSelection()
            }
            .disabled(viewModel.mergeableSelectionCount < 2)
            Button(String(format: NSLocalizedString("context_enqueue_selection", comment: ""), viewModel.multiSelectedIds.count)) {
                viewModel.enqueueSelection()
            }
        } else {
            Button(String(localized: "context_add_to_queue")) {
                viewModel.enqueue(entry: entry)
            }
        }
        if entry.type == .text {
            Button(String(localized: "context_edit")) {
                viewModel.beginEditing(entry: entry)
            }
        }
        Divider()
        Button(String(localized: entry.isPinned ? "context_unpin" : "context_pin")) {
            viewModel.togglePin(entry: entry)
        }
        Divider()
        Button(String(localized: "context_delete"), role: .destructive) {
            viewModel.delete(entry: entry)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(String(localized: "history_hint_navigate"), systemImage: "arrow.up.arrow.down")
            Label(String(localized: "history_hint_paste"), systemImage: "return")
            Text(String(localized: "hint_paste_plain"))
            Text(String(localized: "hint_quick_paste"))
            Text(String(localized: "hint_multi_select"))
            Spacer()
            Label(String(localized: "history_hint_close"), systemImage: "escape")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
}
