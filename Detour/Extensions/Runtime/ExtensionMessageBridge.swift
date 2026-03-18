import Foundation
import WebKit

/// Routes messages between content scripts, background scripts, and native code.
/// Registered as `WKScriptMessageHandler` for the "extensionMessage" handler name.
class ExtensionMessageBridge: NSObject, WKScriptMessageHandler {
    static let shared = ExtensionMessageBridge()
    static let handlerName = "extensionMessage"

    private override init() {
        super.init()
    }

    /// Register the bridge on a WKUserContentController. Safe to call multiple times.
    func register(on controller: WKUserContentController) {
        controller.add(self, name: Self.handlerName)
    }

    /// Register the bridge on a WKUserContentController in a specific content world.
    func register(on controller: WKUserContentController, contentWorld: WKContentWorld) {
        controller.add(self, contentWorld: contentWorld, name: Self.handlerName)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let extensionID = body["extensionID"] as? String,
              let type = body["type"] as? String else { return }

        switch type {
        case "runtime.sendMessage":
            handleSendMessage(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "runtime.sendResponse":
            handleSendResponse(body: body, extensionID: extensionID)

        case "storage.get":
            handleStorageGet(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "storage.set":
            handleStorageSet(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "storage.remove":
            handleStorageRemove(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "storage.clear":
            handleStorageClear(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "tabs.query":
            handleTabsQuery(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "tabs.create":
            handleTabsCreate(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "tabs.update":
            handleTabsUpdate(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "tabs.remove":
            handleTabsRemove(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "tabs.get":
            handleTabsGet(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "tabs.sendMessage":
            handleTabsSendMessage(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "scripting.executeScript":
            handleScriptingExecuteScript(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case "scripting.insertCSS":
            handleScriptingInsertCSS(body: body, extensionID: extensionID, sourceWebView: message.webView)

        default:
            print("[ExtensionBridge] Unknown message type: \(type)")
        }
    }

    // MARK: - Message Routing

    private func handleSendMessage(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let message = body["message"],
              let callbackID = body["callbackID"] as? String else { return }

        guard let ext = ExtensionManager.shared.extension(withID: extensionID),
              let backgroundHost = ExtensionManager.shared.backgroundHost(for: extensionID) else { return }

        // Serialize message to JSON for transport
        guard let messageData = try? JSONSerialization.data(withJSONObject: message),
              let messageJSON = String(data: messageData, encoding: .utf8) else { return }

        let sender: [String: Any] = [
            "id": extensionID,
            "origin": "content-script"
        ]
        guard let senderData = try? JSONSerialization.data(withJSONObject: sender),
              let senderJSON = String(data: senderData, encoding: .utf8) else { return }

        // Dispatch to background script in .page world
        let js = "window.__extensionDispatchMessage(\(messageJSON), \(senderJSON), '\(callbackID)');"
        backgroundHost.evaluateJavaScript(js) { _, error in
            if let error {
                print("[ExtensionBridge] Error dispatching to background: \(error)")
            }
        }

        // Store the source webView to route the response back.
        // Popup/background scripts run in .page world; content scripts run in the extension's content world.
        let isContentScript = body["isContentScript"] as? Bool ?? true
        let responseWorld: WKContentWorld = isContentScript ? ext.contentWorld : .page
        pendingResponses[callbackID] = PendingResponse(
            sourceWebView: sourceWebView,
            contentWorld: responseWorld
        )
    }

    private func handleSendResponse(body: [String: Any], extensionID: String) {
        guard let callbackID = body["callbackID"] as? String,
              let pending = pendingResponses.removeValue(forKey: callbackID) else { return }

        let response = body["response"] ?? [String: Any]()
        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let responseJSON = String(data: responseData, encoding: .utf8) else { return }

        let js = "window.__extensionDeliverResponse('\(callbackID)', \(responseJSON));"

        if let webView = pending.sourceWebView {
            webView.evaluateJavaScript(js, in: nil, in: pending.contentWorld) { _ in }
        }
    }

    // MARK: - Storage Handlers

    private func handleStorageGet(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        let getAll = params["getAll"] as? Bool ?? false
        let result: [String: Any]
        if getAll {
            result = ExtensionDatabase.shared.storageGetAll(extensionID: extensionID)
        } else {
            let keys = params["keys"] as? [String] ?? []
            result = ExtensionDatabase.shared.storageGet(extensionID: extensionID, keys: keys)
        }

        deliverCallbackResponse(callbackID: callbackID, result: result, extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleStorageSet(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let items = params["items"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        ExtensionDatabase.shared.storageSet(extensionID: extensionID, items: items)
        deliverCallbackResponse(callbackID: callbackID, result: [:], extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleStorageRemove(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let keys = params["keys"] as? [String],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        ExtensionDatabase.shared.storageRemove(extensionID: extensionID, keys: keys)
        deliverCallbackResponse(callbackID: callbackID, result: [:], extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleStorageClear(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        ExtensionDatabase.shared.storageClear(extensionID: extensionID)
        deliverCallbackResponse(callbackID: callbackID, result: [:], extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
    }

    private func deliverCallbackResponse(callbackID: String, result: [String: Any], extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        guard let webView else { return }

        guard let resultData = try? JSONSerialization.data(withJSONObject: result),
              let resultJSON = String(data: resultData, encoding: .utf8) else { return }

        let js = "window.__extensionDeliverResponse('\(callbackID)', \(resultJSON));"

        // Deliver to the same world the request came from.
        // Content scripts run in an isolated content world; popups/background run in .page.
        if isContentScript, let ext = ExtensionManager.shared.extension(withID: extensionID) {
            webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
        } else {
            webView.evaluateJavaScript(js) { _, _ in }
        }
    }

    // MARK: - Pending Response Tracking

    private struct PendingResponse {
        weak var sourceWebView: WKWebView?
        let contentWorld: WKContentWorld
    }

    private var pendingResponses: [String: PendingResponse] = [:]

    // MARK: - Tab Info Builder

    /// Build a chrome.tabs.Tab info dictionary from a BrowserTab.
    func buildTabInfo(tab: BrowserTab, space: Space, isActive: Bool) -> [String: Any] {
        let mgr = ExtensionManager.shared
        let tabID = mgr.tabIDMap.intID(for: tab.id)
        let windowID = mgr.spaceIDMap.intID(for: space.id)

        var info: [String: Any] = [
            "id": tabID,
            "windowId": windowID,
            "active": isActive,
            "index": space.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0,
            "pinned": space.pinnedEntries.contains(where: { $0.tab?.id == tab.id }),
            "incognito": space.isIncognito,
            "status": tab.isLoading ? "loading" : "complete"
        ]
        if let url = tab.url {
            info["url"] = url.absoluteString
        }
        info["title"] = tab.title
        if let faviconURL = tab.faviconURL {
            info["favIconUrl"] = faviconURL.absoluteString
        }
        return info
    }

    // MARK: - Tabs Handlers

    private func handleTabsQuery(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true
        let queryInfo = params["queryInfo"] as? [String: Any] ?? [:]

        let filterActive = queryInfo["active"] as? Bool
        let filterCurrentWindow = queryInfo["currentWindow"] as? Bool
        let filterURL = queryInfo["url"] as? String
        let filterTitle = queryInfo["title"] as? String
        let filterWindowId = queryInfo["windowId"] as? Int

        let mgr = ExtensionManager.shared
        var results: [[String: Any]] = []

        for space in TabStore.shared.spaces {
            // Skip incognito unless explicitly requested
            if space.isIncognito { continue }

            let windowID = mgr.spaceIDMap.intID(for: space.id)

            // Filter by currentWindow
            if filterCurrentWindow == true {
                guard space.id == mgr.lastActiveSpaceID else { continue }
            }

            // Filter by windowId
            if let wid = filterWindowId {
                guard windowID == wid else { continue }
            }

            for tab in space.tabs {
                let isActive = space.selectedTabID == tab.id

                if let active = filterActive, active != isActive { continue }

                if let urlPattern = filterURL, let tabURL = tab.url?.absoluteString {
                    if !tabURL.contains(urlPattern) { continue }
                }

                if let titleFilter = filterTitle, !tab.title.contains(titleFilter) { continue }

                results.append(buildTabInfo(tab: tab, space: space, isActive: isActive))
            }

            // Also include live pinned tabs
            for entry in space.pinnedEntries {
                guard let tab = entry.tab else { continue }
                let isActive = space.selectedTabID == tab.id

                if let active = filterActive, active != isActive { continue }
                if let urlPattern = filterURL, let tabURL = tab.url?.absoluteString {
                    if !tabURL.contains(urlPattern) { continue }
                }
                if let titleFilter = filterTitle, !tab.title.contains(titleFilter) { continue }

                results.append(buildTabInfo(tab: tab, space: space, isActive: isActive))
            }
        }

        deliverCallbackResponse(callbackID: callbackID, result: results, extensionID: extensionID,
                                webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleTabsCreate(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true
        let props = params["createProperties"] as? [String: Any] ?? [:]

        let mgr = ExtensionManager.shared
        let urlString = props["url"] as? String
        let url = urlString.flatMap { URL(string: $0) }
        let windowId = props["windowId"] as? Int

        // Resolve target space
        let space: Space
        if let windowId, let spaceUUID = mgr.spaceIDMap.uuid(for: windowId),
           let s = TabStore.shared.space(withID: spaceUUID) {
            space = s
        } else if let activeID = mgr.lastActiveSpaceID,
                  let s = TabStore.shared.space(withID: activeID) {
            space = s
        } else if let s = TabStore.shared.spaces.first {
            space = s
        } else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "No space available"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        let tab = TabStore.shared.addTab(in: space, url: url)
        let active = props["active"] as? Bool ?? true
        if active {
            space.selectedTabID = tab.id
            NotificationCenter.default.post(
                name: Notification.Name("extensionTabShouldSelect"),
                object: nil,
                userInfo: ["tabID": tab.id, "spaceID": space.id]
            )
        }

        let info = buildTabInfo(tab: tab, space: space, isActive: active)
        deliverCallbackResponse(callbackID: callbackID, result: info, extensionID: extensionID,
                                webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleTabsUpdate(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true
        let updateProps = params["updateProperties"] as? [String: Any] ?? [:]

        let mgr = ExtensionManager.shared

        // Resolve tab
        let tabIDInt = params["tabId"] as? Int
        var targetTab: BrowserTab?
        var targetSpace: Space?

        if let tabIDInt, let uuid = mgr.tabIDMap.uuid(for: tabIDInt) {
            (targetTab, targetSpace) = findTab(uuid: uuid)
        } else if let activeID = mgr.lastActiveSpaceID,
                  let space = TabStore.shared.space(withID: activeID),
                  let selectedID = space.selectedTabID {
            (targetTab, targetSpace) = findTab(uuid: selectedID)
        }

        guard let tab = targetTab, let space = targetSpace else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab not found"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        if let urlString = updateProps["url"] as? String, let url = URL(string: urlString) {
            tab.load(url)
        }

        if let active = updateProps["active"] as? Bool, active {
            space.selectedTabID = tab.id
            NotificationCenter.default.post(
                name: Notification.Name("extensionTabShouldSelect"),
                object: nil,
                userInfo: ["tabID": tab.id, "spaceID": space.id]
            )
        }

        if let muted = updateProps["muted"] as? Bool, muted != tab.isMuted {
            tab.toggleMute()
        }

        let isActive = space.selectedTabID == tab.id
        let info = buildTabInfo(tab: tab, space: space, isActive: isActive)
        deliverCallbackResponse(callbackID: callbackID, result: info, extensionID: extensionID,
                                webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleTabsRemove(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let tabIds = params["tabIds"] as? [Int],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        let mgr = ExtensionManager.shared

        for tabIDInt in tabIds {
            guard let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else { continue }
            let (tab, space) = findTab(uuid: uuid)
            if let tab, let space {
                TabStore.shared.closeTab(id: tab.id, in: space)
            }
        }

        deliverCallbackResponse(callbackID: callbackID, result: [:], extensionID: extensionID,
                                webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleTabsGet(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let tabIDInt = params["tabId"] as? Int,
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        let mgr = ExtensionManager.shared
        guard let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab not found"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        let (tab, space) = findTab(uuid: uuid)
        guard let tab, let space else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab not found"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        let isActive = space.selectedTabID == tab.id
        let info = buildTabInfo(tab: tab, space: space, isActive: isActive)
        deliverCallbackResponse(callbackID: callbackID, result: info, extensionID: extensionID,
                                webView: sourceWebView, isContentScript: isContentScript)
    }

    private func handleTabsSendMessage(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let tabIDInt = params["tabId"] as? Int,
              let message = params["message"],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        let mgr = ExtensionManager.shared
        guard let ext = mgr.extension(withID: extensionID),
              let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab not found"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        let (tab, _) = findTab(uuid: uuid)
        guard let tab, let webView = tab.webView else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab has no webView"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        guard let messageData = try? JSONSerialization.data(withJSONObject: message),
              let messageJSON = String(data: messageData, encoding: .utf8) else { return }

        let sender: [String: Any] = ["id": extensionID, "origin": "background"]
        guard let senderData = try? JSONSerialization.data(withJSONObject: sender),
              let senderJSON = String(data: senderData, encoding: .utf8) else { return }

        // Dispatch to the content script world in the target tab
        let js = "window.__extensionDispatchMessage(\(messageJSON), \(senderJSON), '\(callbackID)');"
        webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }

        // Store pending response to route back to the background script
        pendingResponses[callbackID] = PendingResponse(
            sourceWebView: sourceWebView,
            contentWorld: .page  // Response goes back to background (page world)
        )
    }

    // MARK: - Scripting Handlers

    private func handleScriptingExecuteScript(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let injection = params["injection"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        let mgr = ExtensionManager.shared
        guard let ext = mgr.extension(withID: extensionID) else { return }

        let target = injection["target"] as? [String: Any]
        let tabIDInt = target?["tabId"] as? Int

        guard let tabIDInt, let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Target tab required"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        let (tab, _) = findTab(uuid: uuid)
        guard let tab, let webView = tab.webView else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab has no webView"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        var jsToExecute = ""

        if let funcName = injection["func"] as? String {
            let args = injection["args"] as? [Any] ?? []
            if let argsData = try? JSONSerialization.data(withJSONObject: args),
               let argsJSON = String(data: argsData, encoding: .utf8) {
                jsToExecute = "(\(funcName)).apply(null, \(argsJSON))"
            }
        } else if let files = injection["files"] as? [String] {
            var combined = ""
            for file in files {
                let fileURL = ext.basePath.appendingPathComponent(file)
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    combined += content + "\n"
                }
            }
            jsToExecute = combined
        }

        guard !jsToExecute.isEmpty else {
            deliverCallbackResponse(callbackID: callbackID, result: [],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        webView.evaluateJavaScript(jsToExecute, in: nil, in: ext.contentWorld) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let resultItem: [String: Any] = ["result": value ?? NSNull()]
                self.deliverCallbackResponse(callbackID: callbackID, result: [resultItem],
                                             extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            case .failure(let error):
                self.deliverCallbackResponse(callbackID: callbackID, result: ["__error": error.localizedDescription],
                                             extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            }
        }
    }

    private func handleScriptingInsertCSS(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let params = body["params"] as? [String: Any],
              let injection = params["injection"] as? [String: Any],
              let callbackID = body["callbackID"] as? String else { return }
        let isContentScript = body["isContentScript"] as? Bool ?? true

        let mgr = ExtensionManager.shared
        guard let ext = mgr.extension(withID: extensionID) else { return }

        let target = injection["target"] as? [String: Any]
        let tabIDInt = target?["tabId"] as? Int

        guard let tabIDInt, let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Target tab required"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        let (tab, _) = findTab(uuid: uuid)
        guard let tab, let webView = tab.webView else {
            deliverCallbackResponse(callbackID: callbackID, result: ["__error": "Tab has no webView"],
                                    extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
            return
        }

        var cssContent = ""

        if let css = injection["css"] as? String {
            cssContent = css
        } else if let files = injection["files"] as? [String] {
            for file in files {
                let fileURL = ext.basePath.appendingPathComponent(file)
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    cssContent += content + "\n"
                }
            }
        }

        let escapedCSS = cssContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = """
        (function() {
            var style = document.createElement('style');
            style.textContent = '\(escapedCSS)';
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { [weak self] _ in
            self?.deliverCallbackResponse(callbackID: callbackID, result: [:],
                                          extensionID: extensionID, webView: sourceWebView, isContentScript: isContentScript)
        }
    }

    // MARK: - Tab Lookup Helper

    private func findTab(uuid: UUID) -> (BrowserTab?, Space?) {
        for space in TabStore.shared.spaces {
            if let tab = space.tabs.first(where: { $0.id == uuid }) {
                return (tab, space)
            }
            if let entry = space.pinnedEntries.first(where: { $0.tab?.id == uuid }) {
                return (entry.tab, space)
            }
        }
        return (nil, nil)
    }

    // MARK: - Callback Response (array variant)

    private func deliverCallbackResponse(callbackID: String, result: [[String: Any]], extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        guard let webView else { return }

        guard let resultData = try? JSONSerialization.data(withJSONObject: result),
              let resultJSON = String(data: resultData, encoding: .utf8) else { return }

        let js = "window.__extensionDeliverResponse('\(callbackID)', \(resultJSON));"

        if isContentScript, let ext = ExtensionManager.shared.extension(withID: extensionID) {
            webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
        } else {
            webView.evaluateJavaScript(js) { _, _ in }
        }
    }
}
