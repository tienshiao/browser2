import AppKit

// MARK: - TabStoreObserver

extension BrowserWindowController: TabStoreObserver {
    func tabStoreDidInsertTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.insertTab(at: index, tabs: space.tabs)

        if sidebarItem.isCollapsed {
            toastManager.show(message: "Opened new tab in background")
        }
    }

    func tabStoreDidRemoveTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.removeTab(at: index, tabs: space.tabs)
    }

    func tabStoreDidReorderTabs(in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.setTabs(pinned: space.pinnedTabs, normal: space.tabs)
        if let selectedTabID, let index = currentTabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabSidebar.selectedTabIndex = index
        }
    }

    func tabStoreDidUpdateTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.reloadTab(at: index)
    }

    // Pinned tab observer methods

    func tabStoreDidInsertPinnedTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.insertPinnedTab(at: index, pinnedTabs: space.pinnedTabs)
    }

    func tabStoreDidRemovePinnedTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.removePinnedTab(at: index, pinnedTabs: space.pinnedTabs)
    }

    func tabStoreDidPinTab(_ tab: BrowserTab, fromIndex: Int, toIndex: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.pinTab(fromNormalIndex: fromIndex, toPinnedIndex: toIndex,
                          tabs: space.tabs, pinnedTabs: space.pinnedTabs)
    }

    func tabStoreDidUnpinTab(_ tab: BrowserTab, fromIndex: Int, toIndex: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.unpinTab(fromPinnedIndex: fromIndex, toNormalIndex: toIndex,
                            tabs: space.tabs, pinnedTabs: space.pinnedTabs)
    }

    func tabStoreDidReorderPinnedTabs(in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.pinnedTabs = space.pinnedTabs
        if let selectedTabID, let index = space.pinnedTabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabSidebar.selectedPinnedTabIndex = index
        }
    }

    func tabStoreDidUpdatePinnedTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.reloadPinnedTab(at: index)
    }

    func tabStoreDidResetPinnedTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        guard space.id == activeSpaceID else { return }
        tabSidebar.reloadPinnedTab(at: index)
    }

    func tabStoreDidUpdateSpaces() {
        if isIncognito {
            // Incognito windows only show their own space; never switch away
            if let space = activeSpace {
                tabSidebar.updateSpaceButtons(spaces: [space], activeSpaceID: activeSpaceID)
            }
            return
        }

        let nonIncognitoSpaces = store.spaces.filter { !$0.isIncognito }
        tabSidebar.updateSpaceButtons(spaces: nonIncognitoSpaces, activeSpaceID: activeSpaceID)

        // If our active space was deleted, switch to the first available space
        if activeSpaceID == nil || store.space(withID: activeSpaceID!) == nil, let firstSpace = nonIncognitoSpaces.first {
            setActiveSpace(id: firstSpace.id)
        }
    }
}
