import Foundation
import GRDB

struct AppDatabase {
    static let shared = AppDatabase()

    let dbQueue: DatabaseQueue

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MyBrowser", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("browser.db").path

        dbQueue = try! DatabaseQueue(path: dbPath)
        try! migrator.migrate(dbQueue)
    }

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    func saveSession(spaces: [(SpaceRecord, [TabRecord])], lastActiveSpaceID: String?) {
        do {
            try dbQueue.write { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                // Clear existing session data (tabs cascade-deleted via FK)
                try SpaceRecord.deleteAll(db)

                for (spaceRecord, tabRecords) in spaces {
                    try spaceRecord.insert(db)
                    for tabRecord in tabRecords {
                        try tabRecord.insert(db)
                    }
                }

                if let activeID = lastActiveSpaceID {
                    try db.execute(
                        sql: "INSERT INTO appState (key, value) VALUES ('lastActiveSpaceID', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                        arguments: [activeID]
                    )
                }
            }
        } catch {
            print("Failed to save session: \(error)")
        }
    }

    func loadSession() -> (spaces: [(SpaceRecord, [TabRecord])], lastActiveSpaceID: String?)? {
        do {
            return try dbQueue.read { db in
                let spaceRecords = try SpaceRecord.order(Column("sortOrder")).fetchAll(db)
                guard !spaceRecords.isEmpty else { return nil }

                var spaces: [(SpaceRecord, [TabRecord])] = []
                for spaceRecord in spaceRecords {
                    let tabRecords = try TabRecord
                        .filter(Column("spaceID") == spaceRecord.id)
                        .order(Column("sortOrder"))
                        .fetchAll(db)
                    spaces.append((spaceRecord, tabRecords))
                }

                let lastActiveSpaceID = try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = 'lastActiveSpaceID'")
                return (spaces, lastActiveSpaceID)
            }
        } catch {
            print("Failed to load session: \(error)")
            return nil
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "space") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("selectedTabID", .text)
            }

            try db.create(table: "tab") { t in
                t.primaryKey("id", .text)
                t.column("spaceID", .text).notNull()
                    .references("space", onDelete: .cascade)
                t.column("url", .text)
                t.column("title", .text).notNull().defaults(to: "New Tab")
                t.column("faviconURL", .text)
                t.column("interactionState", .blob)
                t.column("sortOrder", .integer).notNull()
            }

            try db.create(table: "appState") { t in
                t.primaryKey("key", .text)
                t.column("value", .text)
            }

        }

        return migrator
    }
}
