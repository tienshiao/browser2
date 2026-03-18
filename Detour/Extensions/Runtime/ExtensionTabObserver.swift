import Foundation
import WebKit

/// Observes TabStore mutations and dispatches chrome.tabs events to all
/// enabled extensions' background hosts.
class ExtensionTabObserver: TabStoreObserver {

    func tabStoreDidInsertTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        let info = ExtensionMessageBridge.shared.buildTabInfo(tab: tab, space: space, isActive: space.selectedTabID == tab.id)
        dispatchTabEvent("onCreated", data: ["tab": info])
    }

    func tabStoreDidRemoveTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        let mgr = ExtensionManager.shared
        let tabID = mgr.tabIDMap.intID(for: tab.id)
        let windowID = mgr.spaceIDMap.intID(for: space.id)
        let removeInfo: [String: Any] = [
            "windowId": windowID,
            "isWindowClosing": false
        ]
        dispatchTabEvent("onRemoved", data: ["tabId": tabID, "removeInfo": removeInfo])
        mgr.tabIDMap.remove(uuid: tab.id)
    }

    func tabStoreDidUpdateTab(_ tab: BrowserTab, at index: Int, in space: Space) {
        let mgr = ExtensionManager.shared
        let tabID = mgr.tabIDMap.intID(for: tab.id)
        let info = ExtensionMessageBridge.shared.buildTabInfo(tab: tab, space: space, isActive: space.selectedTabID == tab.id)

        var changeInfo: [String: Any] = [:]
        changeInfo["status"] = tab.isLoading ? "loading" : "complete"
        if let url = tab.url {
            changeInfo["url"] = url.absoluteString
        }
        changeInfo["title"] = tab.title

        dispatchTabEvent("onUpdated", data: ["tabId": tabID, "changeInfo": changeInfo, "tab": info])
    }

    /// Dispatch a tab activation event. Called externally when tab selection changes.
    func dispatchActivated(tabID: UUID, spaceID: UUID) {
        let mgr = ExtensionManager.shared
        let intTabID = mgr.tabIDMap.intID(for: tabID)
        let intWindowID = mgr.spaceIDMap.intID(for: spaceID)
        let activeInfo: [String: Any] = [
            "tabId": intTabID,
            "windowId": intWindowID
        ]
        dispatchTabEvent("onActivated", data: ["activeInfo": activeInfo])
    }

    // MARK: - Dispatch to Background Hosts

    private func dispatchTabEvent(_ eventName: String, data: [String: Any]) {
        guard let dataJSON = try? JSONSerialization.data(withJSONObject: data),
              let dataString = String(data: dataJSON, encoding: .utf8) else { return }

        let js = "if (window.__extensionDispatchTabEvent) { window.__extensionDispatchTabEvent('\(eventName)', \(dataString)); }"

        for ext in ExtensionManager.shared.enabledExtensions {
            ExtensionManager.shared.backgroundHost(for: ext.id)?.evaluateJavaScript(js)
        }
    }
}
