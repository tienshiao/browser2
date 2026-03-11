import XCTest
import GRDB
@testable import MyBrowser

final class AppDatabaseTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return try AppDatabase(dbQueue: dbQueue)
    }

    // MARK: - saveSession / loadSession round-trip

    func testSaveAndLoadEmptySession() throws {
        let db = try makeDatabase()
        db.saveSession(spaces: [], lastActiveSpaceID: nil)

        let result = db.loadSession()
        XCTAssertNil(result)
    }

    func testSaveAndLoadSingleSpaceWithTabs() throws {
        let db = try makeDatabase()
        let space = SpaceRecord(id: "s1", name: "Home", emoji: "🏠", colorHex: "007AFF", sortOrder: 0, selectedTabID: "t2")
        let tabs = [
            TabRecord(id: "t1", spaceID: "s1", url: "https://a.com", title: "A", faviconURL: nil, interactionState: nil, sortOrder: 0),
            TabRecord(id: "t2", spaceID: "s1", url: "https://b.com", title: "B", faviconURL: "https://b.com/icon.png", interactionState: nil, sortOrder: 1),
        ]

        db.saveSession(spaces: [(space, tabs)], lastActiveSpaceID: "s1")

        let result = db.loadSession()
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.spaces.count, 1)
        XCTAssertEqual(result!.spaces[0].0.id, "s1")
        XCTAssertEqual(result!.spaces[0].0.name, "Home")
        XCTAssertEqual(result!.spaces[0].0.selectedTabID, "t2")
        XCTAssertEqual(result!.spaces[0].1.count, 2)
        XCTAssertEqual(result!.spaces[0].1[0].id, "t1")
        XCTAssertEqual(result!.spaces[0].1[1].id, "t2")
        XCTAssertEqual(result!.lastActiveSpaceID, "s1")
    }

    func testSaveAndLoadMultipleSpacesPreservesOrder() throws {
        let db = try makeDatabase()
        let spaces: [(SpaceRecord, [TabRecord])] = [
            (SpaceRecord(id: "s1", name: "Home", emoji: "🏠", colorHex: "007AFF", sortOrder: 0, selectedTabID: nil), []),
            (SpaceRecord(id: "s2", name: "Work", emoji: "💼", colorHex: "FF3B30", sortOrder: 1, selectedTabID: nil), []),
            (SpaceRecord(id: "s3", name: "Fun", emoji: "🎮", colorHex: "34C759", sortOrder: 2, selectedTabID: nil), []),
        ]

        db.saveSession(spaces: spaces, lastActiveSpaceID: "s2")

        let result = db.loadSession()!
        XCTAssertEqual(result.spaces.map { $0.0.id }, ["s1", "s2", "s3"])
        XCTAssertEqual(result.lastActiveSpaceID, "s2")
    }

    func testTabsReturnedInSortOrder() throws {
        let db = try makeDatabase()
        let space = SpaceRecord(id: "s1", name: "Home", emoji: "🏠", colorHex: "007AFF", sortOrder: 0, selectedTabID: nil)
        let tabs = [
            TabRecord(id: "t3", spaceID: "s1", url: nil, title: "Third", faviconURL: nil, interactionState: nil, sortOrder: 2),
            TabRecord(id: "t1", spaceID: "s1", url: nil, title: "First", faviconURL: nil, interactionState: nil, sortOrder: 0),
            TabRecord(id: "t2", spaceID: "s1", url: nil, title: "Second", faviconURL: nil, interactionState: nil, sortOrder: 1),
        ]

        db.saveSession(spaces: [(space, tabs)], lastActiveSpaceID: nil)

        let result = db.loadSession()!
        XCTAssertEqual(result.spaces[0].1.map(\.id), ["t1", "t2", "t3"])
    }

    func testTabsAreGroupedBySpace() throws {
        let db = try makeDatabase()
        let spaces: [(SpaceRecord, [TabRecord])] = [
            (SpaceRecord(id: "s1", name: "Home", emoji: "🏠", colorHex: "007AFF", sortOrder: 0, selectedTabID: nil), [
                TabRecord(id: "t1", spaceID: "s1", url: nil, title: "Tab 1", faviconURL: nil, interactionState: nil, sortOrder: 0),
            ]),
            (SpaceRecord(id: "s2", name: "Work", emoji: "💼", colorHex: "FF3B30", sortOrder: 1, selectedTabID: nil), [
                TabRecord(id: "t2", spaceID: "s2", url: nil, title: "Tab 2", faviconURL: nil, interactionState: nil, sortOrder: 0),
                TabRecord(id: "t3", spaceID: "s2", url: nil, title: "Tab 3", faviconURL: nil, interactionState: nil, sortOrder: 1),
            ]),
        ]

        db.saveSession(spaces: spaces, lastActiveSpaceID: nil)

        let result = db.loadSession()!
        XCTAssertEqual(result.spaces[0].1.map(\.id), ["t1"])
        XCTAssertEqual(result.spaces[1].1.map(\.id), ["t2", "t3"])
    }

    // MARK: - saveSession replaces previous data

    func testSaveSessionReplacesExistingData() throws {
        let db = try makeDatabase()

        // Save initial session
        db.saveSession(spaces: [
            (SpaceRecord(id: "s1", name: "Old", emoji: "👴", colorHex: "000000", sortOrder: 0, selectedTabID: nil), [
                TabRecord(id: "t1", spaceID: "s1", url: nil, title: "Old Tab", faviconURL: nil, interactionState: nil, sortOrder: 0),
            ]),
        ], lastActiveSpaceID: "s1")

        // Save new session
        db.saveSession(spaces: [
            (SpaceRecord(id: "s2", name: "New", emoji: "✨", colorHex: "FFFFFF", sortOrder: 0, selectedTabID: nil), []),
        ], lastActiveSpaceID: "s2")

        let result = db.loadSession()!
        XCTAssertEqual(result.spaces.count, 1)
        XCTAssertEqual(result.spaces[0].0.id, "s2")
        XCTAssertEqual(result.spaces[0].0.name, "New")
        XCTAssertEqual(result.lastActiveSpaceID, "s2")

        // Verify old tabs are gone too
        try db.dbQueue.read { conn in
            let tabCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM tab")
            XCTAssertEqual(tabCount, 0)
        }
    }

    // MARK: - lastActiveSpaceID

    func testLoadSessionWithNoActiveSpaceID() throws {
        let db = try makeDatabase()
        db.saveSession(spaces: [
            (SpaceRecord(id: "s1", name: "Home", emoji: "🏠", colorHex: "007AFF", sortOrder: 0, selectedTabID: nil), []),
        ], lastActiveSpaceID: nil)

        let result = db.loadSession()!
        XCTAssertNil(result.lastActiveSpaceID)
    }

    // MARK: - Tab data preservation

    func testTabPreservesAllFields() throws {
        let db = try makeDatabase()
        let stateData = "fake-state".data(using: .utf8)
        let space = SpaceRecord(id: "s1", name: "Home", emoji: "🏠", colorHex: "007AFF", sortOrder: 0, selectedTabID: nil)
        let tab = TabRecord(id: "t1", spaceID: "s1", url: "https://example.com", title: "Example", faviconURL: "https://example.com/icon.png", interactionState: stateData, sortOrder: 0)

        db.saveSession(spaces: [(space, [tab])], lastActiveSpaceID: nil)

        let result = db.loadSession()!
        let loaded = result.spaces[0].1[0]
        XCTAssertEqual(loaded.url, "https://example.com")
        XCTAssertEqual(loaded.title, "Example")
        XCTAssertEqual(loaded.faviconURL, "https://example.com/icon.png")
        XCTAssertEqual(loaded.interactionState, stateData)
    }
}
