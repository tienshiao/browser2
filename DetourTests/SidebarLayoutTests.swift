import XCTest
@testable import Detour

final class SidebarLayoutTests: XCTestCase {

    // MARK: - sidebarRow

    func testRow0IsTopSpacer() {
        XCTAssertEqual(sidebarRow(for: 0, pinnedCount: 3), .topSpacer)
        XCTAssertEqual(sidebarRow(for: 0, pinnedCount: 0), .topSpacer)
    }

    func testPinnedTabRows() {
        // With 3 pinned tabs: rows 1, 2, 3
        XCTAssertEqual(sidebarRow(for: 1, pinnedCount: 3), .pinnedTab(index: 0))
        XCTAssertEqual(sidebarRow(for: 2, pinnedCount: 3), .pinnedTab(index: 1))
        XCTAssertEqual(sidebarRow(for: 3, pinnedCount: 3), .pinnedTab(index: 2))
    }

    func testSeparatorRow() {
        // Separator comes right after pinned tabs
        XCTAssertEqual(sidebarRow(for: 4, pinnedCount: 3), .separator)
        XCTAssertEqual(sidebarRow(for: 1, pinnedCount: 0), .separator)
    }

    func testNewTabRow() {
        // New tab comes right after separator
        XCTAssertEqual(sidebarRow(for: 5, pinnedCount: 3), .newTab)
        XCTAssertEqual(sidebarRow(for: 2, pinnedCount: 0), .newTab)
    }

    func testNormalTabRows() {
        // Normal tabs start after new tab row
        XCTAssertEqual(sidebarRow(for: 6, pinnedCount: 3), .normalTab(index: 0))
        XCTAssertEqual(sidebarRow(for: 7, pinnedCount: 3), .normalTab(index: 1))
        XCTAssertEqual(sidebarRow(for: 3, pinnedCount: 0), .normalTab(index: 0))
    }

    func testZeroPinnedLayout() {
        // row 0: topSpacer, 1: separator, 2: newTab, 3+: normalTab
        XCTAssertEqual(sidebarRow(for: 0, pinnedCount: 0), .topSpacer)
        XCTAssertEqual(sidebarRow(for: 1, pinnedCount: 0), .separator)
        XCTAssertEqual(sidebarRow(for: 2, pinnedCount: 0), .newTab)
        XCTAssertEqual(sidebarRow(for: 3, pinnedCount: 0), .normalTab(index: 0))
        XCTAssertEqual(sidebarRow(for: 4, pinnedCount: 0), .normalTab(index: 1))
    }

    // MARK: - rowForNormalTab / rowForPinnedTab

    func testRowForNormalTab() {
        // 1 (topSpacer) + pinnedCount + 1 (separator) + 1 (newTab) + tabIndex
        XCTAssertEqual(rowForNormalTab(at: 0, pinnedCount: 3), 6)
        XCTAssertEqual(rowForNormalTab(at: 2, pinnedCount: 3), 8)
        XCTAssertEqual(rowForNormalTab(at: 0, pinnedCount: 0), 3)
    }

    func testRowForPinnedTab() {
        XCTAssertEqual(rowForPinnedTab(at: 0), 1)
        XCTAssertEqual(rowForPinnedTab(at: 2), 3)
    }

    // MARK: - totalSidebarRowCount

    func testTotalSidebarRowCount() {
        // 1 (topSpacer) + pinnedCount + 1 (separator) + 1 (newTab) + tabCount
        XCTAssertEqual(totalSidebarRowCount(pinnedCount: 3, tabCount: 5), 11)
        XCTAssertEqual(totalSidebarRowCount(pinnedCount: 0, tabCount: 2), 5)
        XCTAssertEqual(totalSidebarRowCount(pinnedCount: 0, tabCount: 0), 3)
    }

    // MARK: - Round-trip

    func testRoundTripNormalTab() {
        for pinnedCount in 0...3 {
            for tabIndex in 0..<5 {
                let row = rowForNormalTab(at: tabIndex, pinnedCount: pinnedCount)
                let result = sidebarRow(for: row, pinnedCount: pinnedCount)
                XCTAssertEqual(result, .normalTab(index: tabIndex),
                               "Round-trip failed for pinnedCount=\(pinnedCount), tabIndex=\(tabIndex)")
            }
        }
    }

    func testRoundTripPinnedTab() {
        for index in 0..<3 {
            let row = rowForPinnedTab(at: index)
            let result = sidebarRow(for: row, pinnedCount: 3)
            XCTAssertEqual(result, .pinnedTab(index: index))
        }
    }
}
