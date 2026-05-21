import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ClipboardStore {
    static let shared = ClipboardStore()
    static let maxEntries = 100

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.clipxs.store", qos: .utility)

    private init() {
        openDatabase()
        createTableIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private var databaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClipXS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    var imagesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClipXS/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func openDatabase() {
        let path = databaseURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func createTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            preview TEXT NOT NULL,
            payload TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_entries_created ON entries(created_at DESC);
        """
        execute(sql)
    }

    private func execute(_ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &error)
        if let error {
            sqlite3_free(error)
        }
    }

    func insert(_ entry: ClipboardEntry, contentHash: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            if self.hasHash(contentHash) {
                self.deleteByHash(contentHash)
            }

            let sql = """
            INSERT INTO entries (id, type, preview, payload, content_hash, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let id = entry.id.uuidString
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entry.type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, entry.preview, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, entry.payload, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, contentHash, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 6, entry.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)

            self.trimToMax()
        }
    }

    private func hasHash(_ hash: String) -> Bool {
        guard let db else { return false }
        let sql = "SELECT 1 FROM entries WHERE content_hash = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
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
        sqlite3_step(stmt)
    }

    private func fetchEntry(hash: String) -> ClipboardEntry? {
        guard let db else { return nil }
        let sql = "SELECT id, type, preview, payload, created_at FROM entries WHERE content_hash = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToEntry(stmt)
    }

    func fetchAll(completion: @escaping ([ClipboardEntry]) -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let sql = "SELECT id, type, preview, payload, created_at FROM entries ORDER BY created_at DESC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(Self.maxEntries))

            var entries: [ClipboardEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let entry = self.rowToEntry(stmt) {
                    entries.append(entry)
                }
            }
            DispatchQueue.main.async { completion(entries) }
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
            sqlite3_step(stmt)
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
            DispatchQueue.main.async { completion?() }
        }
    }

    private func trimToMax() {
        let sql = """
        DELETE FROM entries WHERE id IN (
            SELECT id FROM entries ORDER BY created_at ASC
            LIMIT MAX(0, (SELECT COUNT(*) FROM entries) - \(Self.maxEntries))
        );
        """
        execute(sql)

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
        return ClipboardEntry(id: id, type: type, preview: preview, payload: payload, createdAt: createdAt)
    }
}
