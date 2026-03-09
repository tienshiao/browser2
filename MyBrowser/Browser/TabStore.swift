import Foundation
import Combine

protocol TabStoreObserver: AnyObject {
    func tabStoreDidInsertTab(_ tab: BrowserTab, at index: Int)
    func tabStoreDidRemoveTab(_ tab: BrowserTab, at index: Int)
    func tabStoreDidReorderTabs()
    func tabStoreDidUpdateTab(_ tab: BrowserTab, at index: Int)
}

class TabStore {
    static let shared = TabStore()

    private(set) var tabs: [BrowserTab] = []
    private var observers: [WeakObserver] = []
    private var tabSubscriptions: [UUID: Set<AnyCancellable>] = [:]

    private init() {}

    // MARK: - Observer Management

    func addObserver(_ observer: TabStoreObserver) {
        observers.removeAll { $0.value == nil }
        observers.append(WeakObserver(value: observer))
    }

    func removeObserver(_ observer: TabStoreObserver) {
        observers.removeAll { $0.value === observer || $0.value == nil }
    }

    private func notifyObservers(_ action: (TabStoreObserver) -> Void) {
        observers.removeAll { $0.value == nil }
        for wrapper in observers {
            if let observer = wrapper.value {
                action(observer)
            }
        }
    }

    // MARK: - Tab Mutations

    @discardableResult
    func addTab(url: URL? = nil, afterTabID: UUID? = nil) -> BrowserTab {
        let tab = BrowserTab()

        let insertionIndex: Int
        if let afterTabID, let afterIndex = tabs.firstIndex(where: { $0.id == afterTabID }) {
            insertionIndex = afterIndex + 1
            tabs.insert(tab, at: insertionIndex)
        } else {
            tabs.append(tab)
            insertionIndex = tabs.count - 1
        }

        subscribeToTab(tab)
        notifyObservers { $0.tabStoreDidInsertTab(tab, at: insertionIndex) }

        if let url {
            tab.load(url)
        }

        return tab
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tabSubscriptions.removeValue(forKey: tab.id)
        tabs.remove(at: index)
        notifyObservers { $0.tabStoreDidRemoveTab(tab, at: index) }

        if tabs.isEmpty {
            addTab()
        }
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
        notifyObservers { $0.tabStoreDidReorderTabs() }
    }

    func tab(withID id: UUID) -> BrowserTab? {
        tabs.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    // MARK: - Per-Tab Subscriptions

    private func subscribeToTab(_ tab: BrowserTab) {
        var cancellables = Set<AnyCancellable>()

        tab.$title
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tab] _ in
                guard let self, let tab, let index = self.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                self.notifyObservers { $0.tabStoreDidUpdateTab(tab, at: index) }
            }
            .store(in: &cancellables)

        tab.$url
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tab] _ in
                guard let self, let tab, let index = self.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                self.notifyObservers { $0.tabStoreDidUpdateTab(tab, at: index) }
            }
            .store(in: &cancellables)

        tabSubscriptions[tab.id] = cancellables
    }
}

private struct WeakObserver {
    weak var value: (any TabStoreObserver)?
}
