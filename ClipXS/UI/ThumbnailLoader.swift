import AppKit
import ImageIO
import os
import QuickLookThumbnailing
import SwiftUI

/// Loads downsampled thumbnails so large screenshots never enter memory at
/// full resolution. Image payloads live at UUID-named paths that are never
/// reused, so cached thumbnails can never go stale.
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.clipxs.ClipXS",
        category: "QuickLookThumbnail"
    )

    static func thumbnail(path: String, maxPixel: CGFloat) -> NSImage? {
        let key = "\(path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * 2 // retina
        ]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let size = NSSize(
            width: CGFloat(cgImage.width) / 2,
            height: CGFloat(cgImage.height) / 2
        )
        let image = NSImage(cgImage: cgImage, size: size)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Requests the system representation for a file without blocking the
    /// main thread. `.all` lets Quick Look return a thumbnail, preview, or its
    /// icon representation according to the file type.
    static func quickLookThumbnail(
        for url: URL,
        size: CGSize,
        scale: CGFloat
    ) async throws -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )
        let representation = try await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        return representation.nsImage
    }

    static func logQuickLookFailure(for url: URL, error: Error) {
        logger.error(
            "Quick Look thumbnail generation failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}

/// A cancellation-safe SwiftUI bridge for Quick Look. A completed request is
/// only applied when its URL, target size, and display scale are still current.
struct QuickLookThumbnailView: View {
    enum FailurePresentation {
        case compact
        case detailed
    }

    let url: URL
    let size: CGSize
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    let failurePresentation: FailurePresentation

    @Environment(\.displayScale) private var displayScale
    @State private var activeRequest: RequestKey?
    @State private var image: NSImage?
    @State private var failed = false

    init(
        url: URL,
        size: CGSize,
        contentMode: ContentMode = .fit,
        cornerRadius: CGFloat = 6,
        failurePresentation: FailurePresentation = .compact
    ) {
        self.url = url
        self.size = size
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.failurePresentation = failurePresentation
    }

    var body: some View {
        let request = RequestKey(url: url, size: size, scale: displayScale)

        Group {
            if activeRequest == request, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if activeRequest == request, failed {
                failureView
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "quick_look_loading"))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: request) {
            activeRequest = request
            image = nil
            failed = false

            do {
                let loadedImage = try await ThumbnailLoader.quickLookThumbnail(
                    for: request.url,
                    size: request.size,
                    scale: request.scale
                )
                guard !Task.isCancelled, activeRequest == request else { return }
                image = loadedImage
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, activeRequest == request else { return }
                ThumbnailLoader.logQuickLookFailure(for: request.url, error: error)
                failed = true
            }
        }
    }

    @ViewBuilder
    private var failureView: some View {
        switch failurePresentation {
        case .compact:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.05))
                .help(String(localized: "quick_look_failed"))
                .accessibilityLabel(String(localized: "quick_look_failed"))
        case .detailed:
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16))
                Text(String(localized: "quick_look_failed"))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.05))
        }
    }

    private struct RequestKey: Hashable {
        let url: URL
        let size: CGSize
        let scale: CGFloat
    }
}
