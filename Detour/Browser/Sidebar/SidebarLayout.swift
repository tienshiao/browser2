import Foundation

enum SidebarRow: Equatable {
    case topSpacer
    case pinnedTab(index: Int)
    case separator
    case newTab
    case normalTab(index: Int)
}

func sidebarRow(for row: Int, pinnedCount: Int) -> SidebarRow {
    if row == 0 { return .topSpacer }
    let adjusted = row - 1
    if adjusted < pinnedCount {
        return .pinnedTab(index: adjusted)
    }
    if adjusted == pinnedCount {
        return .separator
    }
    let afterSeparator = adjusted - pinnedCount - 1
    if afterSeparator == 0 {
        return .newTab
    }
    return .normalTab(index: afterSeparator - 1)
}

func rowForNormalTab(at tabIndex: Int, pinnedCount: Int) -> Int {
    return 1 + pinnedCount + 1 + 1 + tabIndex
}

func rowForPinnedTab(at index: Int) -> Int {
    return 1 + index
}

func totalSidebarRowCount(pinnedCount: Int, tabCount: Int) -> Int {
    return 1 + pinnedCount + 1 + 1 + tabCount
}
