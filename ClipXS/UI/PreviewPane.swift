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
            SelectableTextView(text: entry.payload)
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
                        SelectableTextView(
                            text: ocrText,
                            fontSize: 11,
                            textContainerInset: .zero
                        )
                        .frame(maxHeight: 90)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        case .files:
            if entry.fileURLs.count == 1, let url = entry.fileURLs.first {
                singleFilePreview(for: url)
            } else if entry.isImageForDisplay {
                multipleImagePreview(for: entry.fileURLs)
                    .id(entry.id)
            } else {
                multipleFilePreview(for: entry.fileURLs)
            }
        }
    }

    private func singleFilePreview(for url: URL) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let previewSize = CGSize(
                    width: max(1, geometry.size.width - 24),
                    height: max(1, geometry.size.height - 24)
                )

                QuickLookThumbnailView(
                    url: url,
                    size: previewSize,
                    failurePresentation: .detailed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(12)
            }

            Divider()
            fileDetails(for: url)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func multipleImagePreview(for urls: [URL]) -> some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                        // Give each image the same space as a single-file preview.
                        // Keep it readable when the queue reduces the pane height.
                        singleFilePreview(for: url)
                            .frame(height: max(280, geometry.size.height - 24))
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func multipleFilePreview(for urls: [URL]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    HStack(spacing: 10) {
                        QuickLookThumbnailView(
                            url: url,
                            size: CGSize(width: 72, height: 56),
                            failurePresentation: .detailed
                        )
                        fileDetails(for: url)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private func fileDetails(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(url.path)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
