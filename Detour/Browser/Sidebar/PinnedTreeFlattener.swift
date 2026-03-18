import Foundation

enum PinnedItem: Equatable {
    case entry(PinnedEntry, depth: Int)
    case folder(PinnedFolder, depth: Int)

    static func == (lhs: PinnedItem, rhs: PinnedItem) -> Bool {
        switch (lhs, rhs) {
        case (.entry(let a, let d1), .entry(let b, let d2)):
            return a.id == b.id && d1 == d2
        case (.folder(let a, let d1), .folder(let b, let d2)):
            return a.id == b.id && d1 == d2
        default:
            return false
        }
    }

    var depth: Int {
        switch self {
        case .entry(_, let d): return d
        case .folder(_, let d): return d
        }
    }
}

func flattenPinnedTree(
    entries: [PinnedEntry],
    folders: [PinnedFolder],
    collapsedFolderIDs: Set<UUID>,
    selectedTabID: UUID?
) -> [PinnedItem] {
    // Build lookup structures
    let foldersByParent = Dictionary(grouping: folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { $0.parentFolderID }
    let entriesByFolder = Dictionary(grouping: entries.sorted(by: { $0.sortOrder < $1.sortOrder })) { $0.folderID }

    var result: [PinnedItem] = []

    func flatten(parentID: UUID?, depth: Int) {
        // Merge folders and top-level entries at this level, sorted by sortOrder
        var items: [(sortOrder: Int, kind: Either)] = []

        if let childFolders = foldersByParent[parentID] {
            for folder in childFolders {
                items.append((sortOrder: folder.sortOrder, kind: .folder(folder)))
            }
        }
        if let childEntries = entriesByFolder[parentID] {
            for entry in childEntries {
                items.append((sortOrder: entry.sortOrder, kind: .entry(entry)))
            }
        }

        items.sort { $0.sortOrder < $1.sortOrder }

        for item in items {
            switch item.kind {
            case .folder(let folder):
                result.append(.folder(folder, depth: depth))
                let isCollapsed = collapsedFolderIDs.contains(folder.id)
                if isCollapsed {
                    // Show selected tab as exposed row if it's inside this collapsed folder
                    if let selectedTabID, let exposedEntry = findSelectedEntry(in: folder.id, entries: entries, folders: folders, selectedTabID: selectedTabID) {
                        result.append(.entry(exposedEntry, depth: depth + 1))
                    }
                } else {
                    flatten(parentID: folder.id, depth: depth + 1)
                }
            case .entry(let entry):
                result.append(.entry(entry, depth: depth))
            }
        }
    }

    flatten(parentID: nil, depth: 0)
    return result
}

/// Recursively searches for the selected tab within a folder hierarchy.
private func findSelectedEntry(in folderID: UUID, entries: [PinnedEntry], folders: [PinnedFolder], selectedTabID: UUID) -> PinnedEntry? {
    // Check direct children
    if let entry = entries.first(where: { $0.folderID == folderID && $0.tab?.id == selectedTabID }) {
        return entry
    }
    // Check nested folders
    for childFolder in folders where childFolder.parentFolderID == folderID {
        if let entry = findSelectedEntry(in: childFolder.id, entries: entries, folders: folders, selectedTabID: selectedTabID) {
            return entry
        }
    }
    return nil
}

/// Returns the folderID that a drop at the given flattened index should inherit.
/// When dropping "above" an item that is inside a folder, the dropped item should join that folder.
func folderIDForDropIndex(_ index: Int, in items: [PinnedItem]) -> UUID? {
    guard index < items.count else { return nil }
    switch items[index] {
    case .entry(let entry, let depth):
        return depth > 0 ? entry.folderID : nil
    case .folder(let folder, let depth):
        return depth > 0 ? folder.parentFolderID : nil
    }
}

/// Returns the item ID (entry or folder) at the given flattened drop index.
/// The dropped item should appear before this item. Returns nil if past the end.
func itemIDAtDropIndex(_ index: Int, in items: [PinnedItem]) -> UUID? {
    guard index < items.count else { return nil }
    switch items[index] {
    case .entry(let entry, _): return entry.id
    case .folder(let folder, _): return folder.id
    }
}

func pinnedItemID(_ item: PinnedItem) -> UUID {
    switch item {
    case .entry(let e, _): return e.id
    case .folder(let f, _): return f.id
    }
}

private enum Either {
    case folder(PinnedFolder)
    case entry(PinnedEntry)
}
