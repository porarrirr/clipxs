import Combine
import XCTest

/// The same workloads run against the production view model before and after
/// optimization. Fixture creation/loading is outside the timed intervals.
@MainActor
final class HistoryPerformanceTests: XCTestCase {
    func testHistoryInteractionTimings() async {
        let entries = Self.fixtures()
        let model = HistoryViewModel(fetchEntries: { completion in completion(entries) })
        let loaded = expectation(description: "history loaded")
        let subscription = model.$allEntries.dropFirst().prefix(1).sink { _ in loaded.fulfill() }
        model.reload()
        await fulfillment(of: [loaded], timeout: 5)
        withExtendedLifetime(subscription) {}

        var checksum = 0
        let navigation = medianMilliseconds {
            model.typeFilter = .all
            model.searchText = "検索"
            for _ in 0..<40 {
                model.selectNext()
                checksum += model.visibleEntries.count
                checksum += model.selectedEntry == nil ? 0 : 1
                model.selectPrevious()
                checksum += model.visibleEntries.count
            }
        }
        let typing = medianMilliseconds {
            model.typeFilter = .all
            for query in ["検", "検索", "検索対", "検索対象", "検索", ""] {
                model.searchText = query
                // List, preview, and selection each read the visible history.
                checksum += model.visibleEntries.count
                checksum += model.selectedEntry == nil ? 0 : 1
                checksum += model.visibleEntries.count
            }
        }
        let fileFilter = medianMilliseconds {
            model.searchText = ""
            model.typeFilter = .image
            for _ in 0..<40 {
                model.selectNext()
                checksum += model.visibleEntries.count
                checksum += model.selectedEntry == nil ? 0 : 1
                model.selectPrevious()
                checksum += model.visibleEntries.count
            }
        }
        XCTAssertGreaterThan(checksum, 0)
        print("HISTORY_BENCHMARK " + "{\"entries\":1000,\"rounds\":7,\"navigation_ms\":\(navigation),\"typing_ms\":\(typing),\"image_filter_navigation_ms\":\(fileFilter),\"checksum\":\(checksum)}")
    }

    private func medianMilliseconds(_ operation: () -> Void) -> Double {
        operation() // warm up system format/type caches
        let samples = (0..<7).map { _ in
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        return samples.sorted()[samples.count / 2]
    }

    private static func fixtures() -> [ClipboardEntry] {
        (0..<1000).map { index in
            switch index % 5 {
            case 0:
                return ClipboardEntry(type: .text, preview: "Web \(index)", payload: "https://example.com/\(index)")
            case 1:
                return ClipboardEntry(type: .files, preview: "Photo \(index)", payload: "[\"/tmp/photo-\(index).png\",\"/tmp/photo-\(index).heic\"]")
            case 2:
                return ClipboardEntry(type: .files, preview: "Document \(index)", payload: "[\"/tmp/document-\(index).pdf\"]")
            case 3:
                return ClipboardEntry(type: .image, preview: "Image \(index)", payload: "/tmp/image-\(index).png", ocrText: "画像の検索対象 \(index)")
            default:
                return ClipboardEntry(type: .text, preview: "メモ \(index)", payload: String(repeating: "クリップボード履歴の文章です。", count: 40) + "検索対象 \(index)")
            }
        }
    }
}
