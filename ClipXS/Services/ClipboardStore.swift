import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Notification.Name {
    static let clipxsHistoryDidChange = Notification.Name("clipxsHistoryDidChange")
}

final class ClipboardStore {
    static let shared = ClipboardStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.clipxs.store", qos: .utility)
    private let databaseURL: URL
    let imagesDirectory: URL

    /// `databaseURL` is injectable so tests can run against a temporary file.
    init(databaseURL: URL? = nil) {
        let url = databaseURL ?? Self.defaultDatabaseURL()
        self.databaseURL = url
        let imagesDir = url.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        self.imagesDirectory = imagesDir

        openDatabase()
        migrateIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClipXS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    private func openDatabase() {
        let path = databaseURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            NSLog("ClipXS: failed to open database at \(path): \(message)")
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Schema

    private static let schemaVersion: Int32 = 2

    private func migrateIfNeeded() {
        guard db != nil else { return }
        let version = userVersion()
        guard version < Self.schemaVersion else { return }

        if tableExists("entries") {
            if version < 1 {
                backupDatabaseOnce()
            }
            // Idempotent: only add columns that are still missing, so a crash
            // between ALTERs cannot brick the next launch.
            let existing = columnNames()
            if !existing.contains("pinned") {
                execute("ALTER TABLE entries ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;")
            }
            if !existing.contains("rich_payload") {
                execute("ALTER TABLE entries ADD COLUMN rich_payload BLOB;")
            }
            if !existing.contains("rich_format") {
                execute("ALTER TABLE entries ADD COLUMN rich_format TEXT;")
            }
            if !existing.contains("source_bundle_id") {
                execute("ALTER TABLE entries ADD COLUMN source_bundle_id TEXT;")
            }
            if !existing.contains("ocr_text") {
                execute("ALTER TABLE entries ADD COLUMN ocr_text TEXT;")
            }
        } else {
            createTable()
        }
        execute("PRAGMA user_version = \(Self.schemaVersion);")
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            preview TEXT NOT NULL,
            payload TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            rich_payload BLOB,
            rich_format TEXT,
            source_bundle_id TEXT,
            ocr_text TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_entries_created ON entries(created_at DESC);
        """
        execute(sql)
    }

    private func userVersion() -> Int32 {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

    private func tableExists(_ name: String) -> Bool {
        guard let db else { return false }
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func columnNames() -> Set<String> {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(entries);", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) {
                names.insert(String(cString: c))
            }
        }
        return names
    }

    private func backupDatabaseOnce() {
        let backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent(databaseURL.lastPathComponent + ".v0.bak")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try FileManager.default.copyItem(at: databaseURL, to: backupURL)
        } catch {
            NSLog("ClipXS: pre-migration backup failed: \(error.localizedDescription)")
        }
    }

    private func execute(_ sql: String) {
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            NSLog("ClipXS: SQL failed: \(message)")
        }
        if let errorPointer {
            sqlite3_free(errorPointer)
        }
    }

    // MARK: - Writes

    func insert(_ item: CapturedClipboardItem) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let entry = item.entry

            if let imageData = item.imageData {
                do {
                    try imageData.write(to: URL(fileURLWithPath: entry.payload))
                } catch {
                    NSLog("ClipXS: failed to write image file: \(error.localizedDescription)")
                    return
                }
            }

            // Re-copying an existing item moves it to the top; keep its pin.
            var pinned = entry.isPinned
            if let existing = self.fetchEntry(hash: item.contentHash) {
                pinned = pinned || existing.isPinned
                self.deleteByHash(item.contentHash)
            }

            let sql = """
            INSERT INTO entries (id, type, preview, payload, content_hash, created_at, pinned, rich_payload, rich_format, source_bundle_id, ocr_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let id = entry.id.uuidString
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entry.type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, entry.preview, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, entry.payload, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, item.contentHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 6, entry.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 7, pinned ? 1 : 0)
            if let rich = entry.richPayload {
                _ = rich.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 8, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            if let format = entry.richFormat {
                sqlite3_bind_text(stmt, 9, format.rawValue, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            if let source = entry.sourceBundleId {
                sqlite3_bind_text(stmt, 10, source, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            if let ocr = entry.ocrText {
                sqlite3_bind_text(stmt, 11, ocr, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("ClipXS: insert failed: \(String(cString: sqlite3_errmsg(db)))")
            }

            self.purgeExpired()
            self.trimToMax()
            self.notifyChanged()
        }
    }

    /// Replaces the text content of an entry after in-panel editing. The rich
    /// payload is dropped: the edit happened on the plain text, so keeping the
    /// stale rich version would paste content the user no longer sees.
    func updateText(id: UUID, newText: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            UPDATE entries
            SET payload = ?, preview = ?, content_hash = ?, rich_payload = NULL, rich_format = NULL
            WHERE id = ? AND type = 'text';
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, PasteboardCapture.textPreview(from: newText), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, ContentHash.sha256(newText), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("ClipXS: update text failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            self.notifyChanged()
        }
    }

    func updateOCRText(id: UUID, text: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "UPDATE entries SET ocr_text = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("ClipXS: update ocr failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            if sqlite3_changes(db) > 0 {
                self.notifyChanged()
            }
        }
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "UPDATE entries SET pinned = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("ClipXS: set pinned failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            self.notifyChanged()
        }
    }

    func deleteEntry(_ entry: ClipboardEntry) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            if entry.type == .image {
                let url = URL(fileURLWithPath: entry.payload)
                try? FileManager.default.removeItem(at: url)
            }
            let sql = "DELETE FROM entries WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("ClipXS: delete entry failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            self.notifyChanged()
        }
    }

    func clearAll(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.execute("DELETE FROM entries;")
            if let images = try? FileManager.default.contentsOfDirectory(at: self.imagesDirectory, includingPropertiesForKeys: nil) {
                for url in images {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            self.notifyChanged()
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: - Reads

    private static let selectColumns = "id, type, preview, payload, created_at, pinned, rich_payload, rich_format, source_bundle_id, ocr_text"

    func fetchAll(completion: @escaping ([ClipboardEntry]) -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            // Expired rows are purged here (not just on insert) so an idle app
            // still honors the retention setting when the panel opens. The
            // fetch result already reflects the purge, so no change notification
            // is needed (posting one would loop refresh → fetch → refresh).
            self.purgeExpired()
            // No LIMIT: trimToMax already bounds unpinned rows, and pinned rows
            // must never be hidden just because they exceed the cap.
            let sql = "SELECT \(Self.selectColumns) FROM entries ORDER BY pinned DESC, created_at DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            defer { sqlite3_finalize(stmt) }

            var entries: [ClipboardEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let entry = self.rowToEntry(stmt) {
                    entries.append(entry)
                }
            }
            DispatchQueue.main.async { completion(entries) }
        }
    }

    private func fetchEntry(hash: String) -> ClipboardEntry? {
        guard let db else { return nil }
        let sql = "SELECT \(Self.selectColumns) FROM entries WHERE content_hash = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToEntry(stmt)
    }

    private func deleteByHash(_ hash: String) {
        guard let entry = fetchEntry(hash: hash) else { return }
        if entry.type == .image {
            try? FileManager.default.removeItem(atPath: entry.payload)
        }
        guard let db else { return }
        let sql = "DELETE FROM entries WHERE content_hash = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            NSLog("ClipXS: delete by hash failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    // MARK: - Maintenance

    /// Deletes unpinned entries older than the retention setting. Must run on
    /// the store queue. Image files of deleted rows are swept by the orphan
    /// cleanup in `trimToMax`; insert runs both, and fetch runs a sweep too.
    private func purgeExpired() {
        let retention = SettingsAccess.retentionSeconds
        guard retention > 0 else { return }
        let cutoff = Date().timeIntervalSince1970 - Double(retention)
        guard let db else { return }
        let sql = "DELETE FROM entries WHERE pinned = 0 AND created_at < ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        if sqlite3_step(stmt) != SQLITE_DONE {
            NSLog("ClipXS: purge expired failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        if sqlite3_changes(db) > 0 {
            removeOrphanedImages()
        }
    }

    private func trimToMax() {
        let max = SettingsAccess.maxEntries
        let sql = """
        DELETE FROM entries WHERE pinned = 0 AND id IN (
            SELECT id FROM entries WHERE pinned = 0 ORDER BY created_at ASC
            LIMIT MAX(0, (SELECT COUNT(*) FROM entries WHERE pinned = 0) - \(max))
        );
        """
        execute(sql)
        removeOrphanedImages()
    }

    private func removeOrphanedImages() {
        guard let db else { return }
        let orphanSQL = """
        SELECT payload FROM entries WHERE type = 'image';
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, orphanSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        var kept = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                kept.insert(String(cString: c))
            }
        }

        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) {
            for url in files where !kept.contains(url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipxsHistoryDidChange, object: nil)
        }
    }

    private func rowToEntry(_ stmt: OpaquePointer?) -> ClipboardEntry? {
        guard let stmt,
              let idC = sqlite3_column_text(stmt, 0),
              let typeC = sqlite3_column_text(stmt, 1),
              let previewC = sqlite3_column_text(stmt, 2),
              let payloadC = sqlite3_column_text(stmt, 3),
              let type = ClipboardItemType(rawValue: String(cString: typeC)),
              let id = UUID(uuidString: String(cString: idC))
        else { return nil }

        let preview = String(cString: previewC)
        let payload = String(cString: payloadC)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let pinned = sqlite3_column_int(stmt, 5) != 0

        var richPayload: Data?
        if let blob = sqlite3_column_blob(stmt, 6) {
            let count = Int(sqlite3_column_bytes(stmt, 6))
            richPayload = Data(bytes: blob, count: count)
        }
        var richFormat: RichTextFormat?
        if let formatC = sqlite3_column_text(stmt, 7) {
            richFormat = RichTextFormat(rawValue: String(cString: formatC))
        }
        var sourceBundleId: String?
        if let sourceC = sqlite3_column_text(stmt, 8) {
            sourceBundleId = String(cString: sourceC)
        }
        var ocrText: String?
        if let ocrC = sqlite3_column_text(stmt, 9) {
            ocrText = String(cString: ocrC)
        }

        return ClipboardEntry(
            id: id,
            type: type,
            preview: preview,
            payload: payload,
            createdAt: createdAt,
            isPinned: pinned,
            richPayload: richPayload,
            richFormat: richFormat,
            sourceBundleId: sourceBundleId,
            ocrText: ocrText
        )
    }
}
