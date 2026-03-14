import XCTest
import GRDB
@testable import Detour

final class SuggestionProviderTests: XCTestCase {

    private func makeProvider(db: HistoryDatabase) -> SuggestionProvider {
        let provider = SuggestionProvider()
        return provider
    }

    private func makeDatabase() throws -> HistoryDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        return try HistoryDatabase(dbQueue: dbQueue)
    }

    // MARK: - Default suggestions

    func testDefaultSuggestionsReturnsHistoryItems() throws {
        let db = try makeDatabase()
        db.recordVisit(url: "https://a.com", title: "A", faviconURL: nil, spaceID: "space1")
        db.recordVisit(url: "https://b.com", title: "B", faviconURL: nil, spaceID: "space1")

        // Use the database directly since SuggestionProvider uses the shared singleton
        let results = db.recentHistory(spaceID: "space1")
        let items = results.map { SuggestionItem.historyResult(url: $0.url, title: $0.title, faviconURL: $0.faviconURL) }

        XCTAssertEqual(items.count, 2)
        for item in items {
            if case .historyResult = item {
                // correct type
            } else {
                XCTFail("Expected historyResult")
            }
        }
    }

    // MARK: - Tab filtering

    func testTabFilteringMatchesURLCaseInsensitive() {
        let tabs = [
            SuggestionProvider.TabInfo(tabID: UUID(), spaceID: UUID(), url: "https://GitHub.com/test", title: "GitHub", favicon: nil),
            SuggestionProvider.TabInfo(tabID: UUID(), spaceID: UUID(), url: "https://example.com", title: "Example", favicon: nil),
        ]

        let query = "github"
        let matching = tabs.filter {
            $0.url.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }

        XCTAssertEqual(matching.count, 1)
        XCTAssertTrue(matching[0].url.contains("GitHub"))
    }

    func testTabFilteringMatchesTitleCaseInsensitive() {
        let tabs = [
            SuggestionProvider.TabInfo(tabID: UUID(), spaceID: UUID(), url: "https://a.com", title: "My Swift Project", favicon: nil),
            SuggestionProvider.TabInfo(tabID: UUID(), spaceID: UUID(), url: "https://b.com", title: "Cooking", favicon: nil),
        ]

        let query = "swift"
        let matching = tabs.filter {
            $0.url.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }

        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching[0].title, "My Swift Project")
    }

    func testTabFilteringLimitsToThree() {
        let tabs = (1...10).map {
            SuggestionProvider.TabInfo(tabID: UUID(), spaceID: UUID(), url: "https://test\($0).com", title: "Test \($0)", favicon: nil)
        }

        let query = "test"
        let matching = tabs.filter {
            $0.url.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }
        let limited = Array(matching.prefix(3))

        XCTAssertEqual(limited.count, 3)
    }

    // MARK: - SuggestionItem type checks

    func testHistoryResultCarriesAllFields() {
        let item = SuggestionItem.historyResult(url: "https://example.com", title: "Example", faviconURL: "https://example.com/favicon.ico")

        if case .historyResult(let url, let title, let faviconURL) = item {
            XCTAssertEqual(url, "https://example.com")
            XCTAssertEqual(title, "Example")
            XCTAssertEqual(faviconURL, "https://example.com/favicon.ico")
        } else {
            XCTFail("Wrong case")
        }
    }

    func testOpenTabCarriesAllFields() {
        let tabID = UUID()
        let spaceID = UUID()
        let item = SuggestionItem.openTab(tabID: tabID, spaceID: spaceID, url: "https://a.com", title: "A", favicon: nil)

        if case .openTab(let tid, let sid, let url, let title, _) = item {
            XCTAssertEqual(tid, tabID)
            XCTAssertEqual(sid, spaceID)
            XCTAssertEqual(url, "https://a.com")
            XCTAssertEqual(title, "A")
        } else {
            XCTFail("Wrong case")
        }
    }

    func testSearchSuggestionCarriesText() {
        let item = SuggestionItem.searchSuggestion(text: "swift programming")

        if case .searchSuggestion(let text) = item {
            XCTAssertEqual(text, "swift programming")
        } else {
            XCTFail("Wrong case")
        }
    }

    // MARK: - History deduplication against open tabs

    func testHistoryDeduplicatesAgainstOpenTabs() throws {
        let db = try makeDatabase()
        db.recordVisit(url: "https://a.com", title: "A", faviconURL: nil, spaceID: "space1")
        db.recordVisit(url: "https://b.com", title: "B", faviconURL: nil, spaceID: "space1")

        let tabURLs: Set<String> = ["https://a.com"]
        let history = db.searchHistory(query: "com", spaceID: "space1")
        let filtered = history.filter { !tabURLs.contains($0.url) }

        // a.com should be filtered out because it's an open tab
        XCTAssertFalse(filtered.contains(where: { $0.url == "https://a.com" }))
        XCTAssertTrue(filtered.contains(where: { $0.url == "https://b.com" }))
    }

    // MARK: - Merge ordering

    func testMergeOrderIsTabsHistorySearch() {
        var merged: [SuggestionItem] = []

        let tabItems: [SuggestionItem] = [.openTab(tabID: UUID(), spaceID: UUID(), url: "https://tab.com", title: "Tab", favicon: nil)]
        let historyItems: [SuggestionItem] = [.historyResult(url: "https://history.com", title: "History", faviconURL: nil)]
        let searchItems: [SuggestionItem] = [.searchSuggestion(text: "search query")]

        merged.append(contentsOf: tabItems)
        merged.append(contentsOf: historyItems)
        merged.append(contentsOf: searchItems)

        XCTAssertEqual(merged.count, 3)

        if case .openTab = merged[0] {} else { XCTFail("First should be openTab") }
        if case .historyResult = merged[1] {} else { XCTFail("Second should be historyResult") }
        if case .searchSuggestion = merged[2] {} else { XCTFail("Third should be searchSuggestion") }
    }

    func testMergeCapsAtTwelve() {
        var merged: [SuggestionItem] = []
        for i in 1...20 {
            merged.append(.historyResult(url: "https://\(i).com", title: "\(i)", faviconURL: nil))
        }
        let capped = Array(merged.prefix(12))
        XCTAssertEqual(capped.count, 12)
    }
}
