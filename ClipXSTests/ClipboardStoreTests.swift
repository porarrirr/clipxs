import SQLite3
import XCTest

final class ClipboardStoreTests: XCTestCase {
    private var tempDir: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipXSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("history.sqlite")
        UserDefaults.standard.removeObject(forKey: SettingsKeys.maxEntries)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.retentionSeconds)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.maxEntries)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.retentionSeconds)
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func makeItem(
        _ text: String,
        createdAt: Date = Date(),
        richPayload: Data? = nil,
        richFormat: RichTextFormat? = nil,
        sourceBundleId: String? = nil
    ) -> CapturedClipboardItem {
        let entry = ClipboardEntry(
            type: .text,
            preview: text,
            payload: text,
            createdAt: createdAt,
            richPayload: richPayload,
            richFormat: richFormat,
            sourceBundleId: sourceBundleId
        )
        return CapturedClipboardItem(entry: entry, contentHash: "hash-\(text)")
    }

    private func fetchAllSync(_ store: ClipboardStore) -> [ClipboardEntry] {
        let fetched = expectation(description: "fetchAll")
        var result: [ClipboardEntry] = []
        store.fetchAll { entries in
            result = entries
            fetched.fulfill()
        }
        wait(for: [fetched], timeout: 5)
        return result
    }

    // MARK: - Migration

    func testMigratesV0DatabaseKeepingData() throws {
        let entryId = UUID().uuidString
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        let v0SQL = """
        CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            preview TEXT NOT NULL,
            payload TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX idx_entries_created ON entries(created_at DESC);
        INSERT INTO entries VALUES ('\(entryId)', 'text', 'hello', 'hello world', 'h1', 1700000000.0);
        """
        XCTAssertEqual(sqlite3_exec(db, v0SQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let store = ClipboardStore(databaseURL: dbURL)
        let entries = fetchAllSync(store)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id.uuidString, entryId)
        XCTAssertEqual(entries[0].payload, "hello world")
        XCTAssertFalse(entries[0].isPinned)
        XCTAssertNil(entries[0].richPayload)
        XCTAssertNil(entries[0].richFormat)

        XCTAssertEqual(userVersion(of: dbURL), 2)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dbURL.path + ".v0.bak"),
            "pre-migration backup should exist"
        )
    }

    func testMigratesV1DatabaseWithoutBackup() throws {
        let entryId = UUID().uuidString
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        let v1SQL = """
        CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            preview TEXT NOT NULL,
            payload TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            rich_payload BLOB,
            rich_format TEXT
        );
        INSERT INTO entries (id, type, preview, payload, content_hash, created_at)
        VALUES ('\(entryId)', 'text', 'hello', 'hello world', 'h1', 1700000000.0);
        PRAGMA user_version = 1;
        """
        XCTAssertEqual(sqlite3_exec(db, v1SQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let store = ClipboardStore(databaseURL: dbURL)
        let entries = fetchAllSync(store)

        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].sourceBundleId)
        XCTAssertNil(entries[0].ocrText)
        XCTAssertEqual(userVersion(of: dbURL), 2)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dbURL.path + ".v0.bak"),
            "v1→v2 migration must not create the v0 backup"
        )
    }

    func testFreshDatabaseGetsVersionedSchema() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("first"))
        let entries = fetchAllSync(store)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(userVersion(of: dbURL), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path + ".v0.bak"))
    }

    // MARK: - Pinning

    func testDedupPreservesPin() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("dup"))
        var entries = fetchAllSync(store)
        XCTAssertEqual(entries.count, 1)

        store.setPinned(true, id: entries[0].id)
        store.insert(makeItem("dup"))

        entries = fetchAllSync(store)
        XCTAssertEqual(entries.count, 1, "same-hash insert should replace, not duplicate")
        XCTAssertTrue(entries[0].isPinned, "re-copying a pinned item must keep the pin")
    }

    func testTrimExemptsPinnedEntries() {
        UserDefaults.standard.set(10, forKey: SettingsKeys.maxEntries)
        let store = ClipboardStore(databaseURL: dbURL)

        store.insert(makeItem("pin-me", createdAt: Date(timeIntervalSince1970: 1000)))
        let initial = fetchAllSync(store)
        store.setPinned(true, id: initial[0].id)

        for i in 0..<15 {
            store.insert(makeItem("item-\(i)", createdAt: Date(timeIntervalSince1970: 2000 + Double(i))))
        }

        let entries = fetchAllSync(store)
        XCTAssertTrue(
            entries.contains { $0.payload == "pin-me" && $0.isPinned },
            "oldest entry must survive trim because it is pinned"
        )
        XCTAssertEqual(entries.filter { !$0.isPinned }.count, 10)
        XCTAssertEqual(entries.count, 11)
    }

    func testPinnedEntriesSortFirst() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("old", createdAt: Date(timeIntervalSince1970: 1000)))
        store.insert(makeItem("new", createdAt: Date(timeIntervalSince1970: 2000)))

        var entries = fetchAllSync(store)
        XCTAssertEqual(entries.map(\.payload), ["new", "old"])

        let oldEntry = entries.first { $0.payload == "old" }!
        store.setPinned(true, id: oldEntry.id)

        entries = fetchAllSync(store)
        XCTAssertEqual(entries.map(\.payload), ["old", "new"], "pinned entries sort before newer unpinned ones")
    }

    // MARK: - Rich payload

    func testRichPayloadRoundTrip() {
        let store = ClipboardStore(databaseURL: dbURL)
        let rtf = Data("{\\rtf1 hello}".utf8)
        store.insert(makeItem("rich", richPayload: rtf, richFormat: .rtf))

        let entries = fetchAllSync(store)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].richPayload, rtf)
        XCTAssertEqual(entries[0].richFormat, .rtf)
    }

    // MARK: - Source app

    func testSourceBundleIdRoundTrip() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("from-safari", sourceBundleId: "com.apple.Safari"))
        store.insert(makeItem("unknown-source"))

        let entries = fetchAllSync(store)
        XCTAssertEqual(entries.first { $0.payload == "from-safari" }?.sourceBundleId, "com.apple.Safari")
        XCTAssertNil(entries.first { $0.payload == "unknown-source" }?.sourceBundleId)
    }

    // MARK: - OCR text

    func testUpdateOCRTextRoundTrip() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("screenshot"))
        var entries = fetchAllSync(store)
        XCTAssertNil(entries[0].ocrText)

        store.updateOCRText(id: entries[0].id, text: "認識されたテキスト")

        entries = fetchAllSync(store)
        XCTAssertEqual(entries[0].ocrText, "認識されたテキスト")
    }

    // MARK: - Editing

    func testUpdateTextRewritesPreviewHashAndDropsRichPayload() {
        let store = ClipboardStore(databaseURL: dbURL)
        let rtf = Data("{\\rtf1 hello}".utf8)
        store.insert(makeItem("original", richPayload: rtf, richFormat: .rtf))
        var entries = fetchAllSync(store)
        let id = entries[0].id

        store.updateText(id: id, newText: "  edited\ntext  ")

        entries = fetchAllSync(store)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, id)
        XCTAssertEqual(entries[0].payload, "  edited\ntext  ")
        XCTAssertEqual(entries[0].preview, "edited text", "preview must be re-derived from the edited text")
        XCTAssertNil(entries[0].richPayload, "editing drops the stale rich payload")
        XCTAssertNil(entries[0].richFormat)

        // The rewritten hash must dedup against a fresh capture of the same text.
        let duplicate = CapturedClipboardItem(
            entry: ClipboardEntry(type: .text, preview: "edited text", payload: "  edited\ntext  "),
            contentHash: ContentHash.sha256("  edited\ntext  ")
        )
        store.insert(duplicate)
        entries = fetchAllSync(store)
        XCTAssertEqual(entries.count, 1, "edited entry and re-copy of same text must dedup")
    }

    func testUpdateTextIgnoresNonTextEntries() {
        let store = ClipboardStore(databaseURL: dbURL)
        let imageEntry = ClipboardEntry(type: .image, preview: "Image", payload: "/tmp/nonexistent.png")
        store.insert(CapturedClipboardItem(entry: imageEntry, contentHash: "img-hash"))
        var entries = fetchAllSync(store)

        store.updateText(id: entries[0].id, newText: "should not apply")

        entries = fetchAllSync(store)
        XCTAssertEqual(entries[0].payload, "/tmp/nonexistent.png")
    }

    // MARK: - Retention

    func testPurgeExpiredDeletesOldUnpinnedEntriesOnly() {
        let store = ClipboardStore(databaseURL: dbURL)

        // Populate with retention still unlimited, so nothing is purged early.
        let old = Date(timeIntervalSinceNow: -7200)
        store.insert(makeItem("old-unpinned", createdAt: old))
        store.insert(makeItem("old-pinned", createdAt: old))
        store.insert(makeItem("fresh"))

        var entries = fetchAllSync(store)
        let pinTarget = entries.first { $0.payload == "old-pinned" }!
        store.setPinned(true, id: pinTarget.id)

        // Now enable a 1-hour retention and trigger the purge that runs on insert.
        UserDefaults.standard.set(3600, forKey: SettingsKeys.retentionSeconds)
        store.insert(makeItem("trigger"))

        entries = fetchAllSync(store)
        let payloads = entries.map(\.payload)
        XCTAssertFalse(payloads.contains("old-unpinned"), "expired unpinned entry must be purged")
        XCTAssertTrue(payloads.contains("old-pinned"), "pinned entries are exempt from retention")
        XCTAssertTrue(payloads.contains("fresh"))
        XCTAssertTrue(payloads.contains("trigger"))
    }

    func testUnlimitedRetentionKeepsOldEntries() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("ancient", createdAt: Date(timeIntervalSince1970: 1000)))
        store.insert(makeItem("trigger"))

        let entries = fetchAllSync(store)
        XCTAssertTrue(entries.map(\.payload).contains("ancient"))
    }

    // MARK: - Delete

    func testDeleteEntryRemovesRow() {
        let store = ClipboardStore(databaseURL: dbURL)
        store.insert(makeItem("keep"))
        store.insert(makeItem("remove"))

        var entries = fetchAllSync(store)
        XCTAssertEqual(entries.count, 2)

        let target = entries.first { $0.payload == "remove" }!
        store.deleteEntry(target)

        entries = fetchAllSync(store)
        XCTAssertEqual(entries.map(\.payload), ["keep"])
    }

    // MARK: - Utilities

    private func userVersion(of url: URL) -> Int32 {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int(stmt, 0)
    }
}
