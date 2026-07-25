import AppKit
import SwiftUI

struct PreviewPane: View {
    @ObservedObject var viewModel: HistoryViewModel

    @FocusState private var editorFocused: Bool

    private var entry: ClipboardEntry? {
        viewModel.selectedEntry
    }

    var body: some View {
        Group {
            if let entry {
                VStack(spacing: 0) {
                    if viewModel.editingEntryId == entry.id {
                        editor
                    } else {
                        content(for: entry)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Divider()
                    metadata(for: entry)
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(String(localized: "preview_placeholder"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Editing

    private var editor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.editingText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($editorFocused)
                .onAppear { editorFocused = true }
            Divider()
            HStack(spacing: 8) {
                Text(String(localized: "edit_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(String(localized: "cancel")) {
                    viewModel.cancelEditing()
                }
                .controlSize(.small)
                Button(String(localized: "edit_save")) {
                    viewModel.commitEditing()
                }
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for entry: ClipboardEntry) -> some View {
        switch entry.type {
        case .text:
            ScrollView {
                Text(entry.payload)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        case .image:
            VStack(spacing: 0) {
                if let image = ThumbnailLoader.thumbnail(path: entry.payload, maxPixel: 480) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                        .frame(maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .frame(maxHeight: .infinity)
                }
                if let ocrText = entry.ocrText, !ocrText.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "preview_ocr_label"), systemImage: "text.viewfinder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(ocrText)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(entry.fileURLs.enumerated()), id: \.offset) { _, url in
                        HStack(spacing: 10) {
                            QuickLookThumbnailView(
                                url: url,
                                size: CGSize(width: 72, height: 56),
                                failurePresentation: .detailed
                            )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Text(url.path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private func metadata(for entry: ClipboardEntry) -> some View {
        HStack(spacing: 10) {
            if entry.isPinned {
                Label(String(localized: "preview_pinned"), systemImage: "pin.fill")
            }
            if entry.type == .text {
                Text(String(format: NSLocalizedString("preview_char_count", comment: ""), entry.payload.count))
                if entry.richFormat != nil {
                    Text(String(localized: "preview_rich_text"))
                }
            }
            if let bundleId = entry.sourceBundleId,
               let appName = SourceAppInfo.name(for: bundleId) {
                HStack(spacing: 3) {
                    if let icon = SourceAppInfo.icon(for: bundleId) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    Text(appName)
                }
            }
            Spacer()
            Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
