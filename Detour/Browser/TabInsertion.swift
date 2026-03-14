import Foundation

/// Computes the insertion index for a new tab given its parent and the existing tab list.
/// - Parameters:
///   - parentID: The ID of the parent tab (if any).
///   - existingTabs: The current tabs as (id, parentID) tuples.
///   - pinnedTabIDs: IDs of pinned tabs (parent in pinned section → insert at front of normal tabs).
/// - Returns: The index at which the new tab should be inserted.
func tabInsertionIndex(
    parentID: UUID?,
    existingTabs: [(id: UUID, parentID: UUID?)],
    pinnedTabIDs: Set<UUID>
) -> Int {
    guard let parentID else {
        return 0
    }

    let parentIsNormalTab = !pinnedTabIDs.contains(parentID)
        && existingTabs.contains(where: { $0.id == parentID })

    if parentIsNormalTab, let parentIndex = existingTabs.firstIndex(where: { $0.id == parentID }) {
        var lastSiblingIndex = parentIndex
        for i in (parentIndex + 1)..<existingTabs.count {
            if existingTabs[i].parentID == parentID { lastSiblingIndex = i }
            else { break }
        }
        return lastSiblingIndex + 1
    } else {
        // Pinned parent (or parent not found) → first normal tab, after existing siblings
        var lastSiblingIndex = -1
        for i in 0..<existingTabs.count {
            if existingTabs[i].parentID == parentID { lastSiblingIndex = i }
            else if lastSiblingIndex >= 0 { break }
        }
        return lastSiblingIndex + 1
    }
}
