import AppKit
import SwiftUI

struct HistoryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    /// Part of the ⌘-click multi-selection for merge/queue actions.
    let isMultiSelected: Bool
    /// 0-based position among visible entries; rows 0–8 show a ⌘1–⌘9 badge.
    let index: Int

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .lineLimit(2)
                    .font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(typeLabel)
                    Text(Self.relativeFormatter.localizedString(for: entry.createdAt, relativeTo: Date()))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
            }

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isMultiSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var leadingIcon: some View {
        baseIcon
            .overlay(alignment: .bottomTrailing) {
                if let bundleId = entry.sourceBundleId,
                   let appIcon = SourceAppInfo.icon(for: bundleId) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .offset(x: 4, y: 4)
                }
            }
    }

    @ViewBuilder
    private var baseIcon: some View {
        if entry.type == .image, let image = ThumbnailLoader.thumbnail(path: entry.payload, maxPixel: 40) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if entry.type == .files, let url = entry.fileURLs.first {
            QuickLookThumbnailView(
                url: url,
                size: CGSize(width: 40, height: 40),
                contentMode: .fill
            )
        } else {
            Image(systemName: iconName)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    private var iconName: String {
        if entry.isLink { return "link" }
        switch entry.type {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }

    private var typeLabel: String {
        if entry.isLink { return NSLocalizedString("type_link", comment: "") }
        if entry.isImageForDisplay { return NSLocalizedString("type_image", comment: "") }
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
