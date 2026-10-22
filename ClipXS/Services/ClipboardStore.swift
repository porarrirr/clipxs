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
        guard let stmt = SQLiteStatement(database: db, sql: "PRAGMA user_version;") else { return 0 }
        guard stmt.step() == SQLITE_ROW else { return 0 }
        return stmt.int(at: 0)
    }

    private func tableExists(_ name: String) -> Bool {
        guard let db else { return false }
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        guard let stmt = SQLiteStatement(database: db, sql: sql) else { return false }
        stmt.bind(name, at: 1)
        return stmt.step() == SQLITE_ROW
    }

    private func columnNames() -> Set<String> {
        guard let db else { return [] }
        guard let stmt = SQLiteStatement(database: db, sql: "PRAGMA table_info(entries);") else { return [] }
        var names = Set<String>()
        while stmt.step() == SQLITE_ROW {
            if let name = stmt.text(at: 1) {
                names.insert(name)
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
            guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }

            let id = entry.id.uuidString
            stmt.bind(id, at: 1)
            stmt.bind(entry.type.rawValue, at: 2)
            stmt.bind(entry.preview, at: 3)
            stmt.bind(entry.payload, at: 4)
            stmt.bind(item.contentHash, at: 5)
            stmt.bind(entry.createdAt.timeIntervalSince1970, at: 6)
            stmt.bind(pinned, at: 7)
            stmt.bind(entry.richPayload, at: 8)
            stmt.bind(entry.richFormat?.rawValue, at: 9)
            stmt.bind(entry.sourceBundleId, at: 10)
            stmt.bind(entry.ocrText, at: 11)
            if stmt.step() != SQLITE_DONE {
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
            guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }
            stmt.bind(newText, at: 1)
            stmt.bind(PasteboardCapture.textPreview(from: newText), at: 2)
            stmt.bind(ContentHash.sha256(newText), at: 3)
            stmt.bind(id.uuidString, at: 4)
            if stmt.step() != SQLITE_DONE {
                NSLog("ClipXS: update text failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            self.notifyChanged()
        }
    }

    func updateOCRText(id: UUID, text: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "UPDATE entries SET ocr_text = ? WHERE id = ?;"
            guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }
            stmt.bind(text, at: 1)
            stmt.bind(id.uuidString, at: 2)
            if stmt.step() != SQLITE_DONE {
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
            guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }
            stmt.bind(pinned, at: 1)
            stmt.bind(id.uuidString, at: 2)
            if stmt.step() != SQLITE_DONE {
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
            guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }
            stmt.bind(entry.id.uuidString, at: 1)
            if stmt.step() != SQLITE_DONE {
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
            guard let stmt = SQLiteStatement(database: db, sql: sql) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            var entries: [ClipboardEntry] = []
            while stmt.step() == SQLITE_ROW {
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
        guard let stmt = SQLiteStatement(database: db, sql: sql) else { return nil }
        stmt.bind(hash, at: 1)
        guard stmt.step() == SQLITE_ROW else { return nil }
        return rowToEntry(stmt)
    }

    private func deleteByHash(_ hash: String) {
        guard let entry = fetchEntry(hash: hash) else { return }
        if entry.type == .image {
            try? FileManager.default.removeItem(atPath: entry.payload)
        }
        guard let db else { return }
        let sql = "DELETE FROM entries WHERE content_hash = ?;"
        guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }
        stmt.bind(hash, at: 1)
        if stmt.step() != SQLITE_DONE {
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
        guard let stmt = SQLiteStatement(database: db, sql: sql) else { return }
        stmt.bind(cutoff, at: 1)
        if stmt.step() != SQLITE_DONE {
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
        guard let stmt = SQLiteStatement(database: db, sql: orphanSQL) else { return }
        var kept = Set<String>()
        while stmt.step() == SQLITE_ROW {
            if let path = stmt.text(at: 0) {
                kept.insert(path)
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

    private func rowToEntry(_ stmt: SQLiteStatement) -> ClipboardEntry? {
        guard let idText = stmt.text(at: 0),
              let typeText = stmt.text(at: 1),
              let preview = stmt.text(at: 2),
              let payload = stmt.text(at: 3),
              let type = ClipboardItemType(rawValue: typeText),
              let id = UUID(uuidString: idText)
        else { return nil }

        return ClipboardEntry(
            id: id,
            type: type,
            preview: preview,
            payload: payload,
            createdAt: Date(timeIntervalSince1970: stmt.double(at: 4)),
            isPinned: stmt.int(at: 5) != 0,
            richPayload: stmt.data(at: 6),
            richFormat: stmt.text(at: 7).flatMap(RichTextFormat.init(rawValue:)),
            sourceBundleId: stmt.text(at: 8),
            ocrText: stmt.text(at: 9)
        )
    }
}

/// Owns one prepared statement. Use only on the database's serial queue (or
/// during initialization), and keep bindings alive through SQLite's copy mode.
private final class SQLiteStatement {
    private let handle: OpaquePointer

    init?(database: OpaquePointer, sql: String) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return nil
        }
        handle = statement
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ value: String?, at index: Int32) {
        if let value {
            sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    func bind(_ value: Data?, at index: Int32) {
        if let value {
            _ = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(handle, index, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(handle, index)
        }
    }

    func bind(_ value: Double, at index: Int32) {
        sqlite3_bind_double(handle, index, value)
    }

    func bind(_ value: Bool, at index: Int32) {
        sqlite3_bind_int(handle, index, value ? 1 : 0)
    }

    func step() -> Int32 {
        sqlite3_step(handle)
    }

    func text(at column: Int32) -> String? {
        guard let value = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: value)
    }

    func data(at column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(handle, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, column)))
    }

    func int(at column: Int32) -> Int32 {
        sqlite3_column_int(handle, column)
    }

    func double(at column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }
}
