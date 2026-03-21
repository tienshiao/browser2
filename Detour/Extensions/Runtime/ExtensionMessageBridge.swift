import Foundation
import WebKit

/// Message type constants for the extension bridge dispatch.
private enum MsgType {
    static let runtimeSendMessage = "runtime.sendMessage"
    static let runtimeSendResponse = "runtime.sendResponse"
    static let runtimeConnect = "runtime.connect"
    static let runtimeOpenOptionsPage = "runtime.openOptionsPage"
    static let runtimeSetUninstallURL = "runtime.setUninstallURL"

    static let storageGet = "storage.get"
    static let storageSet = "storage.set"
    static let storageRemove = "storage.remove"
    static let storageClear = "storage.clear"
    static let storageSyncGet = "storage.sync.get"
    static let storageSyncSet = "storage.sync.set"
    static let storageSyncRemove = "storage.sync.remove"
    static let storageSyncClear = "storage.sync.clear"

    static let tabsQuery = "tabs.query"
    static let tabsCreate = "tabs.create"
    static let tabsUpdate = "tabs.update"
    static let tabsRemove = "tabs.remove"
    static let tabsGet = "tabs.get"
    static let tabsSendMessage = "tabs.sendMessage"
    static let tabsDetectLanguage = "tabs.detectLanguage"

    static let scriptingExecuteScript = "scripting.executeScript"
    static let scriptingInsertCSS = "scripting.insertCSS"

    static let contextMenusCreate = "contextMenus.create"
    static let contextMenusUpdate = "contextMenus.update"
    static let contextMenusRemove = "contextMenus.remove"
    static let contextMenusRemoveAll = "contextMenus.removeAll"

    static let offscreenCreateDocument = "offscreen.createDocument"
    static let offscreenCloseDocument = "offscreen.closeDocument"
    static let offscreenHasDocument = "offscreen.hasDocument"

    static let portPostMessage = "port.postMessage"
    static let portDisconnect = "port.disconnect"

    static let resourceGet = "resource.get"

    static let actionSetIcon = "action.setIcon"
    static let actionSetBadgeText = "action.setBadgeText"
    static let actionSetBadgeBackgroundColor = "action.setBadgeBackgroundColor"
    static let actionGetBadgeText = "action.getBadgeText"
    static let actionSetTitle = "action.setTitle"
    static let actionGetTitle = "action.getTitle"
    static let actionSetPopup = "action.setPopup"

    static let commandsGetAll = "commands.getAll"

    static let windowsGetAll = "windows.getAll"
    static let windowsGet = "windows.get"
    static let windowsGetCurrent = "windows.getCurrent"
    static let windowsCreate = "windows.create"
    static let windowsUpdate = "windows.update"

    static let fontSettingsGetFontList = "fontSettings.getFontList"
    static let permissionsContains = "permissions.contains"
}

/// Routes messages between content scripts, background scripts, and native code.
/// Registered as `WKScriptMessageHandler` for the "extensionMessage" handler name.
class ExtensionMessageBridge: NSObject, WKScriptMessageHandler {
    static let shared = ExtensionMessageBridge()
    static let handlerName = "extensionMessage"

    private var messageCount = 0

    /// Bundles the common context extracted from every incoming message.
    private struct MessageContext {
        let callbackID: String
        let extensionID: String
        let isContentScript: Bool
        weak var sourceWebView: WKWebView?

        static func from(body: [String: Any], extensionID: String, webView: WKWebView?) -> MessageContext? {
            guard let callbackID = body["callbackID"] as? String else { return nil }
            let isContentScript = body["isContentScript"] as? Bool ?? true
            return MessageContext(callbackID: callbackID, extensionID: extensionID,
                                 isContentScript: isContentScript, sourceWebView: webView)
        }
    }

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

        // Periodic cleanup of stale entries
        messageCount += 1
        if messageCount % 50 == 0 {
            cleanupOrphanedResponses()
            cleanupStaleCachedDocumentIds()
        }

        // Centralized permission gate
        let callbackID = body["callbackID"] as? String
        let isContentScript = body["isContentScript"] as? Bool ?? true

        if let requiredPermission = ExtensionPermissionChecker.requiredPermission(for: type) {
            guard let ext = ExtensionManager.shared.extension(withID: extensionID),
                  ExtensionPermissionChecker.hasPermission(requiredPermission, extension: ext) else {
                if let cbID = callbackID {
                    let errorMsg = ExtensionPermissionChecker.apiPermissionError(
                        permission: requiredPermission, api: type)
                    deliverCallbackResponse(callbackID: cbID, result: ["__error": errorMsg],
                        extensionID: extensionID, webView: message.webView, isContentScript: isContentScript)
                }
                return
            }
        }

        let ctx = MessageContext.from(body: body, extensionID: extensionID, webView: message.webView)

        switch type {
        case MsgType.runtimeSendMessage:
            guard let ctx else { return }
            handleSendMessage(ctx: ctx, body: body)

        case MsgType.runtimeSendResponse:
            guard let ctx else { return }
            handleSendResponse(ctx: ctx, body: body)

        case MsgType.storageGet:
            guard let ctx else { return }
            handleStorageGet(ctx: ctx, body: body, keyPrefix: "", areaName: "local")

        case MsgType.storageSet:
            guard let ctx else { return }
            handleStorageSet(ctx: ctx, body: body, keyPrefix: "", areaName: "local")

        case MsgType.storageRemove:
            guard let ctx else { return }
            handleStorageRemove(ctx: ctx, body: body, keyPrefix: "", areaName: "local")

        case MsgType.storageClear:
            guard let ctx else { return }
            handleStorageClear(ctx: ctx, body: body, keyPrefix: "", areaName: "local")

        case MsgType.tabsQuery:
            guard let ctx else { return }
            handleTabsQuery(ctx: ctx, body: body)

        case MsgType.tabsCreate:
            guard let ctx else { return }
            handleTabsCreate(ctx: ctx, body: body)

        case MsgType.tabsUpdate:
            guard let ctx else { return }
            handleTabsUpdate(ctx: ctx, body: body)

        case MsgType.tabsRemove:
            guard let ctx else { return }
            handleTabsRemove(ctx: ctx, body: body)

        case MsgType.tabsGet:
            guard let ctx else { return }
            handleTabsGet(ctx: ctx, body: body)

        case MsgType.tabsSendMessage:
            guard let ctx else { return }
            handleTabsSendMessage(ctx: ctx, body: body)

        case MsgType.scriptingExecuteScript:
            guard let ctx else { return }
            handleScriptingExecuteScript(ctx: ctx, body: body)

        case MsgType.scriptingInsertCSS:
            guard let ctx else { return }
            handleScriptingInsertCSS(ctx: ctx, body: body)

        case MsgType.tabsDetectLanguage:
            guard let ctx else { return }
            handleTabsDetectLanguage(ctx: ctx, body: body)

        case MsgType.contextMenusCreate:
            guard let ctx else { return }
            handleContextMenusCreate(ctx: ctx, body: body)

        case MsgType.contextMenusUpdate:
            guard let ctx else { return }
            handleContextMenusUpdate(ctx: ctx, body: body)

        case MsgType.contextMenusRemove:
            guard let ctx else { return }
            handleContextMenusRemove(ctx: ctx, body: body)

        case MsgType.contextMenusRemoveAll:
            guard let ctx else { return }
            handleContextMenusRemoveAll(ctx: ctx, body: body)

        case MsgType.offscreenCreateDocument:
            guard let ctx else { return }
            handleOffscreenCreateDocument(ctx: ctx, body: body)

        case MsgType.offscreenCloseDocument:
            guard let ctx else { return }
            handleOffscreenCloseDocument(ctx: ctx, body: body)

        case MsgType.offscreenHasDocument:
            guard let ctx else { return }
            handleOffscreenHasDocument(ctx: ctx, body: body)

        case MsgType.runtimeConnect:
            handleRuntimeConnect(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case MsgType.portPostMessage:
            handlePortPostMessage(body: body, extensionID: extensionID, sourceWebView: message.webView)

        case MsgType.portDisconnect:
            handlePortDisconnect(body: body, extensionID: extensionID)

        case MsgType.runtimeOpenOptionsPage:
            handleRuntimeOpenOptionsPage(ctx: ctx, body: body)

        case MsgType.resourceGet:
            handleResourceGet(ctx: ctx, body: body)

        // Storage sync handlers
        case MsgType.storageSyncGet:
            guard let ctx else { return }
            handleStorageGet(ctx: ctx, body: body, keyPrefix: "sync:", areaName: "sync")
        case MsgType.storageSyncSet:
            guard let ctx else { return }
            handleStorageSet(ctx: ctx, body: body, keyPrefix: "sync:", areaName: "sync")
        case MsgType.storageSyncRemove:
            guard let ctx else { return }
            handleStorageRemove(ctx: ctx, body: body, keyPrefix: "sync:", areaName: "sync")
        case MsgType.storageSyncClear:
            guard let ctx else { return }
            handleStorageClear(ctx: ctx, body: body, keyPrefix: "sync:", areaName: "sync")

        // Action handlers
        case MsgType.actionSetIcon:
            guard let ctx else { return }
            handleActionSetIcon(ctx: ctx, body: body)
        case MsgType.actionSetBadgeText:
            guard let ctx else { return }
            handleActionSetBadgeText(ctx: ctx, body: body)
        case MsgType.actionSetBadgeBackgroundColor:
            guard let ctx else { return }
            handleActionSetBadgeBackgroundColor(ctx: ctx, body: body)
        case MsgType.actionGetBadgeText:
            guard let ctx else { return }
            handleActionGetBadgeText(ctx: ctx, body: body)
        case MsgType.actionSetTitle:
            guard let ctx else { return }
            handleActionSetTitle(ctx: ctx, body: body)
        case MsgType.actionGetTitle:
            guard let ctx else { return }
            handleActionGetTitle(ctx: ctx, body: body)
        case MsgType.actionSetPopup:
            guard let ctx else { return }
            handleActionSetPopup(ctx: ctx, body: body)

        // Commands handler
        case MsgType.commandsGetAll:
            guard let ctx else { return }
            handleCommandsGetAll(ctx: ctx, body: body)

        // Windows handlers
        case MsgType.windowsGetAll:
            guard let ctx else { return }
            handleWindowsGetAll(ctx: ctx, body: body)
        case MsgType.windowsGet:
            guard let ctx else { return }
            handleWindowsGet(ctx: ctx, body: body)
        case MsgType.windowsGetCurrent:
            guard let ctx else { return }
            handleWindowsGetCurrent(ctx: ctx, body: body)
        case MsgType.windowsCreate:
            guard let ctx else { return }
            handleWindowsCreate(ctx: ctx, body: body)
        case MsgType.windowsUpdate:
            guard let ctx else { return }
            handleWindowsUpdate(ctx: ctx, body: body)

        // Font settings handler
        case MsgType.fontSettingsGetFontList:
            guard let ctx else { return }
            handleFontSettingsGetFontList(ctx: ctx, body: body)

        // Permissions handler
        case MsgType.permissionsContains:
            guard let ctx else { return }
            handlePermissionsContains(ctx: ctx, body: body)

        // Runtime: setUninstallURL
        case MsgType.runtimeSetUninstallURL:
            guard let ctx else { return }
            handleRuntimeSetUninstallURL(ctx: ctx, body: body)

        default:
            print("[ExtensionBridge] Unknown message type: \(type)")
        }
    }

    // MARK: - Message Routing

    private func handleSendMessage(ctx: MessageContext, body: [String: Any]) {
        guard let message = body["message"] else { return }

        guard let ext = ExtensionManager.shared.extension(withID: ctx.extensionID) else { return }

        // Serialize message to JSON for transport
        guard let messageData = try? JSONSerialization.data(withJSONObject: message),
              let messageJSON = String(data: messageData, encoding: .utf8) else { return }

        var sender: [String: Any] = [
            "id": ctx.extensionID,
            "origin": ctx.isContentScript ? "content-script" : "extension"
        ]
        // Include sender URL — extensions like Dark Reader check sender.url to verify popup origin.
        if let senderURL = ctx.sourceWebView?.url?.absoluteString {
            sender["url"] = senderURL
        }
        // For content scripts, include sender.tab, sender.frameId, and sender.documentId.
        // Extensions like Dark Reader use sender.tab.id and sender.documentId to track
        // which documents have content scripts.
        if ctx.isContentScript, let sourceWebView = ctx.sourceWebView {
            // Use the frameId from the payload (0 for top frame, non-zero for subframes).
            // This is critical: Chrome assigns unique frameIds per frame, and extensions
            // like Dark Reader use sender.frameId to track documents. Without unique IDs,
            // iframe DOCUMENT_CONNECTs overwrite the main frame's entry in TabManager.
            let frameId = body["frameId"] as? Int ?? 0
            sender["frameId"] = frameId
            if let documentId = body["documentId"] as? String {
                sender["documentId"] = documentId
                // Cache top-frame documentId for fast verification in tabs.sendMessage
                if frameId == 0 {
                    cachedDocumentIds[ObjectIdentifier(sourceWebView)] = documentId
                }
            }
            if let (tab, space) = findTabByWebView(sourceWebView) {
                let isActive = space.selectedTabID == tab.id
                sender["tab"] = buildTabInfo(tab: tab, space: space, isActive: isActive, includeURLFields: true, extension: ext)
            }
        }
        guard let senderData = try? JSONSerialization.data(withJSONObject: sender),
              let senderJSON = String(data: senderData, encoding: .utf8) else { return }

        // Broadcast to all extension contexts (background, offscreen, popup) except the sender.
        // This matches Chrome's runtime.sendMessage semantics.
        let js = "window.__extensionDispatchMessage(\(messageJSON), \(senderJSON), '\(ctx.callbackID)');"

        var targetWebViews: [WKWebView] = []
        if let bgWV = ExtensionManager.shared.backgroundHost(for: ctx.extensionID)?.webView {
            targetWebViews.append(bgWV)
        }
        if let osWV = ExtensionManager.shared.offscreenHosts[ctx.extensionID]?.webView {
            targetWebViews.append(osWV)
        }
        if let popupWV = ExtensionManager.shared.popupWebView(for: ctx.extensionID) {
            targetWebViews.append(popupWV)
        }

        // Exclude the sender so it doesn't receive its own message
        targetWebViews.removeAll { $0 === ctx.sourceWebView }

        // Intercept audio playback messages and handle natively.
        // WebKit's AudioContext doesn't work in hidden WKWebViews without user gesture,
        // so we play audio via AVAudioPlayer in the offscreen host instead.
        if let msgDict = message as? [String: Any] {
            let action = msgDict["action"] as? String
            if action == "playAudio",
               let audioSrc = msgDict["audioSrc"] as? String,
               let osHost = ExtensionManager.shared.offscreenHosts[ctx.extensionID] {
                osHost.playAudioNatively(base64: audioSrc)
                deliverResponse(ctx, result: [:] as [String: Any])
                return
            }
            if action == "pauseAudio",
               let osHost = ExtensionManager.shared.offscreenHosts[ctx.extensionID] {
                osHost.stopAudioNatively()
                deliverResponse(ctx, result: [:] as [String: Any])
                return
            }
        }

        for webView in targetWebViews {
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[ExtensionBridge] Error dispatching message: \(error)")
                }
            }
        }

        // Store the source webView to route the response back.
        // Popup/background scripts run in .page world; content scripts run in the extension's content world.
        let responseWorld: WKContentWorld = ctx.isContentScript ? ext.contentWorld : .page
        pendingResponses[ctx.callbackID] = PendingResponse(
            sourceWebView: ctx.sourceWebView,
            contentWorld: responseWorld
        )
    }

    private func handleSendResponse(ctx: MessageContext, body: [String: Any]) {
        guard let pending = pendingResponses.removeValue(forKey: ctx.callbackID) else { return }

        let response = body["response"] ?? [String: Any]()
        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let responseJSON = String(data: responseData, encoding: .utf8) else { return }

        let js = "window.__extensionDeliverResponse('\(ctx.callbackID)', \(responseJSON));"

        if let webView = pending.sourceWebView {
            webView.evaluateJavaScript(js, in: nil, in: pending.contentWorld) { _ in }
        }
    }

    // MARK: - Storage Handlers

    private func handleStorageGet(ctx: MessageContext, body: [String: Any], keyPrefix: String, areaName: String) {
        guard let params = body["params"] as? [String: Any] else { return }

        let getAll = params["getAll"] as? Bool ?? false
        let result: [String: Any]
        if keyPrefix.isEmpty {
            if getAll {
                result = AppDatabase.shared.storageGetAll(extensionID: ctx.extensionID)
            } else {
                let keys = params["keys"] as? [String] ?? []
                result = AppDatabase.shared.storageGet(extensionID: ctx.extensionID, keys: keys)
            }
        } else {
            if getAll {
                let allItems = AppDatabase.shared.storageGetAll(extensionID: ctx.extensionID)
                var filtered: [String: Any] = [:]
                for (key, value) in allItems where key.hasPrefix(keyPrefix) {
                    filtered[String(key.dropFirst(keyPrefix.count))] = value
                }
                result = filtered
            } else {
                let keys = params["keys"] as? [String] ?? []
                let prefixedKeys = keys.map { keyPrefix + $0 }
                let rawResult = AppDatabase.shared.storageGet(extensionID: ctx.extensionID, keys: prefixedKeys)
                var filtered: [String: Any] = [:]
                for (key, value) in rawResult where key.hasPrefix(keyPrefix) {
                    filtered[String(key.dropFirst(keyPrefix.count))] = value
                }
                result = filtered
            }
        }

        deliverResponse(ctx, result: result)
    }

    private func handleStorageSet(ctx: MessageContext, body: [String: Any], keyPrefix: String, areaName: String) {
        guard let params = body["params"] as? [String: Any],
              let items = params["items"] as? [String: Any] else { return }

        // Read old values before writing to compute changes
        let prefixedKeys = items.keys.map { keyPrefix + $0 }
        let oldPrefixed = AppDatabase.shared.storageGet(extensionID: ctx.extensionID, keys: prefixedKeys)

        // Write with prefix
        var prefixedItems: [String: Any] = [:]
        for (key, value) in items { prefixedItems[keyPrefix + key] = value }
        AppDatabase.shared.storageSet(extensionID: ctx.extensionID, items: prefixedItems)
        deliverResponse(ctx, result: [:] as [String: Any])

        // Broadcast storage.onChanged with unprefixed keys
        var changes: [String: Any] = [:]
        for (key, newValue) in items {
            var change: [String: Any] = ["newValue": newValue]
            if let old = oldPrefixed[keyPrefix + key] { change["oldValue"] = old }
            changes[key] = change
        }
        broadcastStorageChanged(changes: changes, areaName: areaName, extensionID: ctx.extensionID, sourceWebView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
    }

    private func handleStorageRemove(ctx: MessageContext, body: [String: Any], keyPrefix: String, areaName: String) {
        guard let params = body["params"] as? [String: Any],
              let keys = params["keys"] as? [String] else { return }

        // Read old values before removing
        let prefixedKeys = keys.map { keyPrefix + $0 }
        let oldPrefixed = AppDatabase.shared.storageGet(extensionID: ctx.extensionID, keys: prefixedKeys)

        AppDatabase.shared.storageRemove(extensionID: ctx.extensionID, keys: prefixedKeys)
        deliverResponse(ctx, result: [:] as [String: Any])

        // Broadcast storage.onChanged with unprefixed keys
        var changes: [String: Any] = [:]
        for key in keys {
            if let old = oldPrefixed[keyPrefix + key] {
                changes[key] = ["oldValue": old]
            }
        }
        if !changes.isEmpty {
            broadcastStorageChanged(changes: changes, areaName: areaName, extensionID: ctx.extensionID, sourceWebView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
        }
    }

    private func handleStorageClear(ctx: MessageContext, body: [String: Any], keyPrefix: String, areaName: String) {
        // Read all values before clearing
        let allValues = AppDatabase.shared.storageGetAll(extensionID: ctx.extensionID)

        if keyPrefix.isEmpty {
            AppDatabase.shared.storageClear(extensionID: ctx.extensionID)
        } else {
            let keysToRemove = allValues.keys.filter { $0.hasPrefix(keyPrefix) }
            AppDatabase.shared.storageRemove(extensionID: ctx.extensionID, keys: Array(keysToRemove))
        }
        deliverResponse(ctx, result: [:] as [String: Any])

        // Broadcast storage.onChanged with unprefixed keys
        var changes: [String: Any] = [:]
        for (key, oldValue) in allValues where key.hasPrefix(keyPrefix) {
            let unprefixedKey = String(key.dropFirst(keyPrefix.count))
            changes[unprefixedKey] = ["oldValue": oldValue]
        }
        if !changes.isEmpty {
            broadcastStorageChanged(changes: changes, areaName: areaName, extensionID: ctx.extensionID, sourceWebView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
        }
    }

    private func deliverCallbackResponse(callbackID: String, result: [String: Any], extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        guard let resultData = try? JSONSerialization.data(withJSONObject: result),
              let resultJSON = String(data: resultData, encoding: .utf8) else { return }
        deliverJS("window.__extensionDeliverResponse('\(callbackID)', \(resultJSON));",
                  extensionID: extensionID, webView: webView, isContentScript: isContentScript)
    }

    // MARK: - MessageContext Delivery

    private func deliverResponse(_ ctx: MessageContext, result: [String: Any]) {
        deliverCallbackResponse(callbackID: ctx.callbackID, result: result, extensionID: ctx.extensionID, webView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
    }

    private func deliverResponse(_ ctx: MessageContext, result: String) {
        deliverCallbackResponse(callbackID: ctx.callbackID, result: result, extensionID: ctx.extensionID, webView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
    }

    private func deliverResponse(_ ctx: MessageContext, result: Bool) {
        deliverCallbackResponse(callbackID: ctx.callbackID, result: result, extensionID: ctx.extensionID, webView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
    }

    private func deliverResponse(_ ctx: MessageContext, result: [[String: Any]]) {
        deliverCallbackResponse(callbackID: ctx.callbackID, result: result, extensionID: ctx.extensionID, webView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
    }

    // MARK: - Pending Response Tracking

    private struct PendingResponse {
        weak var sourceWebView: WKWebView?
        let contentWorld: WKContentWorld
    }

    private var pendingResponses: [String: PendingResponse] = [:]

    /// Cached top-frame documentId per tab webView. Updated when content scripts send
    /// runtime.sendMessage with frameId=0. Used to verify tabs.sendMessage documentId
    /// without an async evaluateJavaScript round-trip.
    private var cachedDocumentIds: [ObjectIdentifier: String] = [:]

    // MARK: - Tab Info Builder

    /// Build a chrome.tabs.Tab info dictionary from a BrowserTab.
    /// When `includeURLFields` is false, sensitive fields (url, title, favIconUrl) are
    /// omitted, matching Chrome's behavior when the "tabs" permission is absent.
    /// Chrome also includes URL fields when the extension has host permissions for the tab's URL.
    func buildTabInfo(tab: BrowserTab, space: Space, isActive: Bool, includeURLFields: Bool = true, extension ext: WebExtension? = nil) -> [String: Any] {
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
        // Include URL fields if the extension has the "tabs" permission OR has host permission for this tab's URL.
        // This matches Chrome's behavior: host_permissions grant access to URL-sensitive fields for matching tabs.
        var shouldIncludeURL = includeURLFields
        if !shouldIncludeURL, let ext, let tabURL = tab.url {
            shouldIncludeURL = ExtensionPermissionChecker.hasHostPermission(for: tabURL, extension: ext)
        }
        if shouldIncludeURL {
            if let url = tab.url { info["url"] = url.absoluteString }
            info["title"] = tab.title
            if let faviconURL = tab.faviconURL { info["favIconUrl"] = faviconURL.absoluteString }
        }
        return info
    }

    // MARK: - Tabs Handlers

    private func handleTabsQuery(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any] else { return }
        let queryInfo = params["queryInfo"] as? [String: Any] ?? [:]

        let filterActive = queryInfo["active"] as? Bool
        let filterCurrentWindow = queryInfo["currentWindow"] as? Bool
        let filterLastFocusedWindow = queryInfo["lastFocusedWindow"] as? Bool
        let filterURL = queryInfo["url"] as? String
        let filterTitle = queryInfo["title"] as? String
        let filterWindowId = queryInfo["windowId"] as? Int

        let mgr = ExtensionManager.shared
        let ext = mgr.extension(withID: ctx.extensionID)
        let includeURLFields = ext.map { ExtensionPermissionChecker.hasPermission("tabs", extension: $0) } ?? true
        var results: [[String: Any]] = []

        for space in TabStore.shared.spaces {
            // Skip incognito unless explicitly requested
            if space.isIncognito { continue }

            let windowID = mgr.spaceIDMap.intID(for: space.id)

            // Filter by currentWindow or lastFocusedWindow
            if filterCurrentWindow == true || filterLastFocusedWindow == true {
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

                results.append(buildTabInfo(tab: tab, space: space, isActive: isActive, includeURLFields: includeURLFields, extension: ext))
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

                results.append(buildTabInfo(tab: tab, space: space, isActive: isActive, includeURLFields: includeURLFields, extension: ext))
            }
        }

        deliverResponse(ctx, result: results)
    }

    private func handleTabsCreate(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any] else { return }
        let props = params["createProperties"] as? [String: Any] ?? [:]

        let mgr = ExtensionManager.shared
        let ext = mgr.extension(withID: ctx.extensionID)
        let includeURLFields = ext.map { ExtensionPermissionChecker.hasPermission("tabs", extension: $0) } ?? true
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
            deliverResponse(ctx, result: ["__error": "No space available"])
            return
        }

        let tab = TabStore.shared.addTab(in: space, url: url)
        let active = props["active"] as? Bool ?? true
        if active {
            space.selectedTabID = tab.id
            NotificationCenter.default.post(
                name: ExtensionManager.tabShouldSelectNotification,
                object: nil,
                userInfo: ["tabID": tab.id, "spaceID": space.id]
            )
        }

        let info = buildTabInfo(tab: tab, space: space, isActive: active, includeURLFields: includeURLFields, extension: ext)
        deliverResponse(ctx, result: info)
    }

    private func handleTabsUpdate(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any] else { return }
        let updateProps = params["updateProperties"] as? [String: Any] ?? [:]

        let mgr = ExtensionManager.shared
        let ext = mgr.extension(withID: ctx.extensionID)
        let includeURLFields = ext.map { ExtensionPermissionChecker.hasPermission("tabs", extension: $0) } ?? true

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
            deliverResponse(ctx, result: ["__error": "Tab not found"])
            return
        }

        if let urlString = updateProps["url"] as? String, let url = URL(string: urlString) {
            tab.load(url)
        }

        if let active = updateProps["active"] as? Bool, active {
            space.selectedTabID = tab.id
            NotificationCenter.default.post(
                name: ExtensionManager.tabShouldSelectNotification,
                object: nil,
                userInfo: ["tabID": tab.id, "spaceID": space.id]
            )
        }

        if let muted = updateProps["muted"] as? Bool, muted != tab.isMuted {
            tab.toggleMute()
        }

        let isActive = space.selectedTabID == tab.id
        let info = buildTabInfo(tab: tab, space: space, isActive: isActive, includeURLFields: includeURLFields, extension: ext)
        deliverResponse(ctx, result: info)
    }

    private func handleTabsRemove(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let tabIds = params["tabIds"] as? [Int] else { return }

        let mgr = ExtensionManager.shared

        for tabIDInt in tabIds {
            guard let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else { continue }
            let (tab, space) = findTab(uuid: uuid)
            if let tab, let space {
                TabStore.shared.closeTab(id: tab.id, in: space)
            }
        }

        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleTabsGet(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let tabIDInt = params["tabId"] as? Int else { return }

        let mgr = ExtensionManager.shared
        let ext = mgr.extension(withID: ctx.extensionID)
        let includeURLFields = ext.map { ExtensionPermissionChecker.hasPermission("tabs", extension: $0) } ?? true
        guard let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverResponse(ctx, result: ["__error": "Tab not found"])
            return
        }

        let (tab, space) = findTab(uuid: uuid)
        guard let tab, let space else {
            deliverResponse(ctx, result: ["__error": "Tab not found"])
            return
        }

        let isActive = space.selectedTabID == tab.id
        let info = buildTabInfo(tab: tab, space: space, isActive: isActive, includeURLFields: includeURLFields, extension: ext)
        deliverResponse(ctx, result: info)
    }

    private func handleTabsSendMessage(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let tabIDInt = params["tabId"] as? Int,
              let message = params["message"] else { return }

        let mgr = ExtensionManager.shared
        guard let ext = mgr.extension(withID: ctx.extensionID),
              let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverResponse(ctx, result: ["__error": "Tab not found"])
            return
        }

        let (tab, _) = findTab(uuid: uuid)
        guard let tab, let webView = tab.webView else {
            deliverResponse(ctx, result: ["__error": "Tab has no webView"])
            return
        }

        // Host permission check
        if let tabURL = tab.url, !ExtensionPermissionChecker.hasHostPermission(for: tabURL, extension: ext) {
            deliverResponse(ctx, result: ["__error": ExtensionPermissionChecker.hostPermissionError(url: tabURL)])
            return
        }

        guard let messageData = try? JSONSerialization.data(withJSONObject: message),
              let messageJSON = String(data: messageData, encoding: .utf8) else { return }

        let sender: [String: Any] = ["id": ctx.extensionID, "origin": "background"]
        guard let senderData = try? JSONSerialization.data(withJSONObject: sender),
              let senderJSON = String(data: senderData, encoding: .utf8) else { return }

        let options = params["options"] as? [String: Any] ?? [:]
        let targetDocumentId = options["documentId"] as? String

        // Helper to deliver the message and store the pending response
        let deliverMessage = { [weak self] in
            let js = "window.__extensionDispatchMessage(\(messageJSON), \(senderJSON), '\(ctx.callbackID)');"
            webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
            self?.pendingResponses[ctx.callbackID] = PendingResponse(
                sourceWebView: ctx.sourceWebView,
                contentWorld: .page  // Response goes back to background (page world)
            )
        }

        // Verify documentId for top-frame messages. For iframe messages (non-zero frameId),
        // deliver unconditionally — the content script's own scriptId check filters correctly.
        // We can't verify iframe documentIds because evaluateJavaScript only runs in the top frame.
        let targetFrameId = options["frameId"] as? Int
        if let targetDocumentId, (targetFrameId == nil || targetFrameId == 0) {
            // Fast path: check cached documentId (populated by runtime.sendMessage from content scripts)
            if let cachedDocId = cachedDocumentIds[ObjectIdentifier(webView)] {
                if cachedDocId != targetDocumentId {
                    deliverResponse(ctx, result: ["__error": "Could not establish connection. Receiving end does not exist."])
                    return
                }
            } else {
                // Slow path: cache miss (e.g. no runtime.sendMessage yet), verify via evaluateJavaScript
                webView.evaluateJavaScript("window.__detourDocumentId", in: nil, in: ext.contentWorld) { [weak self] result in
                    if case .success(let value) = result,
                       let currentDocId = value as? String {
                        self?.cachedDocumentIds[ObjectIdentifier(webView)] = currentDocId
                        if currentDocId == targetDocumentId {
                            deliverMessage()
                        } else {
                            self?.deliverResponse(ctx, result: ["__error": "Could not establish connection. Receiving end does not exist."])
                        }
                    } else {
                        self?.deliverResponse(ctx, result: ["__error": "Could not establish connection. Receiving end does not exist."])
                    }
                }
                return
            }
        }

        // No documentId filter — deliver to all
        deliverMessage()
    }

    // MARK: - Scripting Handlers

    private func handleScriptingExecuteScript(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let injection = params["injection"] as? [String: Any] else { return }

        let mgr = ExtensionManager.shared
        guard let ext = mgr.extension(withID: ctx.extensionID) else { return }

        let target = injection["target"] as? [String: Any]
        let tabIDInt = target?["tabId"] as? Int

        guard let tabIDInt, let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverResponse(ctx, result: ["__error": "Target tab required"])
            return
        }

        let (tab, _) = findTab(uuid: uuid)
        guard let tab, let webView = tab.webView else {
            deliverResponse(ctx, result: ["__error": "Tab has no webView"])
            return
        }

        // Host permission check for programmatic script injection
        if let tabURL = tab.url, !ExtensionPermissionChecker.hasHostPermission(for: tabURL, extension: ext) {
            deliverResponse(ctx, result: ["__error": ExtensionPermissionChecker.hostPermissionError(url: tabURL)])
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
            deliverResponse(ctx, result: [] as [[String: Any]])
            return
        }

        webView.evaluateJavaScript(jsToExecute, in: nil, in: ext.contentWorld) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let resultItem: [String: Any] = ["result": value ?? NSNull()]
                self.deliverResponse(ctx, result: [resultItem])
            case .failure(let error):
                self.deliverResponse(ctx, result: ["__error": error.localizedDescription])
            }
        }
    }

    private func handleScriptingInsertCSS(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let injection = params["injection"] as? [String: Any] else { return }

        let mgr = ExtensionManager.shared
        guard let ext = mgr.extension(withID: ctx.extensionID) else { return }

        let target = injection["target"] as? [String: Any]
        let tabIDInt = target?["tabId"] as? Int

        guard let tabIDInt, let uuid = mgr.tabIDMap.uuid(for: tabIDInt) else {
            deliverResponse(ctx, result: ["__error": "Target tab required"])
            return
        }

        let (tab, _) = findTab(uuid: uuid)
        guard let tab, let webView = tab.webView else {
            deliverResponse(ctx, result: ["__error": "Tab has no webView"])
            return
        }

        // Host permission check for programmatic CSS injection
        if let tabURL = tab.url, !ExtensionPermissionChecker.hasHostPermission(for: tabURL, extension: ext) {
            deliverResponse(ctx, result: ["__error": ExtensionPermissionChecker.hostPermissionError(url: tabURL)])
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

        let escapedCSS = cssContent.jsEscapedForSingleQuotes

        let js = """
        (function() {
            var style = document.createElement('style');
            style.textContent = '\(escapedCSS)';
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { [weak self] _ in
            self?.deliverResponse(ctx, result: [:] as [String: Any])
        }
    }

    // MARK: - Tabs: detectLanguage

    private func handleTabsDetectLanguage(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        let mgr = ExtensionManager.shared
        let tabIDInt = params["tabId"] as? Int

        var targetTab: BrowserTab?
        if let tabIDInt, let uuid = mgr.tabIDMap.uuid(for: tabIDInt) {
            (targetTab, _) = findTab(uuid: uuid)
        } else if let activeID = mgr.lastActiveSpaceID,
                  let space = TabStore.shared.space(withID: activeID),
                  let selectedID = space.selectedTabID {
            (targetTab, _) = findTab(uuid: selectedID)
        }

        guard let tab = targetTab, let webView = tab.webView else {
            deliverResponse(ctx, result: "und")
            return
        }

        webView.evaluateJavaScript("document.documentElement.lang || ''") { [weak self] result, _ in
            let lang = (result as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "und"
            self?.deliverResponse(ctx, result: lang)
        }
    }

    // MARK: - Context Menus Handlers

    private func handleContextMenusCreate(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let properties = params["properties"] as? [String: Any] else { return }

        let item = ContextMenuItem(
            id: properties["id"] as? String ?? UUID().uuidString,
            title: properties["title"] as? String ?? "",
            contexts: properties["contexts"] as? [String] ?? ["page"],
            parentId: properties["parentId"] as? String,
            type: properties["type"] as? String ?? "normal",
            extensionID: ctx.extensionID
        )

        ExtensionManager.shared.addContextMenuItem(item, for: ctx.extensionID)
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleContextMenusUpdate(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let menuItemId = params["menuItemId"] as? String,
              let properties = params["properties"] as? [String: Any] else { return }

        ExtensionManager.shared.updateContextMenuItem(id: menuItemId, properties: properties, for: ctx.extensionID)
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleContextMenusRemove(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        if let menuItemId = params["menuItemId"] as? String {
            ExtensionManager.shared.removeContextMenuItem(id: menuItemId, for: ctx.extensionID)
        }
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleContextMenusRemoveAll(ctx: MessageContext, body: [String: Any]) {
        ExtensionManager.shared.removeAllContextMenuItems(for: ctx.extensionID)
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    // MARK: - Offscreen Document Handlers

    private func handleOffscreenCreateDocument(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let url = params["url"] as? String else { return }

        guard let ext = ExtensionManager.shared.extension(withID: ctx.extensionID) else {
            deliverResponse(ctx, result: ["__error": "Extension not found"])
            return
        }

        let host = OffscreenDocumentHost(extension: ext)
        ExtensionManager.shared.offscreenHosts[ctx.extensionID] = host

        // Delay the callback until the offscreen document finishes loading,
        // so the caller's next sendMessage finds the onMessage listener registered.
        host.load(url: url) { [weak self] in
            self?.deliverResponse(ctx, result: [:] as [String: Any])
        }
    }

    private func handleOffscreenCloseDocument(ctx: MessageContext, body: [String: Any]) {
        ExtensionManager.shared.offscreenHosts[ctx.extensionID]?.stop()
        ExtensionManager.shared.offscreenHosts.removeValue(forKey: ctx.extensionID)

        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleOffscreenHasDocument(ctx: MessageContext, body: [String: Any]) {
        let hasDoc = ExtensionManager.shared.offscreenHosts[ctx.extensionID] != nil
        deliverResponse(ctx, result: hasDoc)
    }

    // MARK: - Port (runtime.connect) Handlers

    private struct PortConnection {
        weak var sourceWebView: WKWebView?
        let sourceContentWorld: WKContentWorld
        weak var targetWebView: WKWebView?
        let targetContentWorld: WKContentWorld
        let portID: String
    }

    private var openPorts: [String: PortConnection] = [:]

    private func cleanupOrphanedPorts() {
        let orphaned = openPorts.filter { $0.value.sourceWebView == nil && $0.value.targetWebView == nil }
        for portID in orphaned.keys {
            openPorts.removeValue(forKey: portID)
        }
        cleanupOrphanedResponses()
        cleanupStaleCachedDocumentIds()
    }

    private func cleanupOrphanedResponses() {
        let orphaned = pendingResponses.filter { $0.value.sourceWebView == nil }
        for key in orphaned.keys {
            pendingResponses.removeValue(forKey: key)
        }
    }

    private func cleanupStaleCachedDocumentIds() {
        let liveWebViewIDs: Set<ObjectIdentifier> = {
            var ids = Set<ObjectIdentifier>()
            for space in TabStore.shared.spaces {
                for tab in space.tabs {
                    if let wv = tab.webView { ids.insert(ObjectIdentifier(wv)) }
                }
                for entry in space.pinnedEntries {
                    if let wv = entry.tab?.webView { ids.insert(ObjectIdentifier(wv)) }
                }
            }
            return ids
        }()
        for key in cachedDocumentIds.keys where !liveWebViewIDs.contains(key) {
            cachedDocumentIds.removeValue(forKey: key)
        }
    }

    private func handleRuntimeConnect(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        cleanupOrphanedPorts()
        guard let portID = body["portID"] as? String else { return }
        let name = body["name"] as? String ?? ""
        let isContentScript = body["isContentScript"] as? Bool ?? true

        guard let ext = ExtensionManager.shared.extension(withID: extensionID),
              let backgroundHost = ExtensionManager.shared.backgroundHost(for: extensionID) else { return }

        let sourceWorld: WKContentWorld = isContentScript ? ext.contentWorld : .page

        // Store the port connection
        openPorts[portID] = PortConnection(
            sourceWebView: sourceWebView,
            sourceContentWorld: sourceWorld,
            targetWebView: backgroundHost.webView,
            targetContentWorld: .page,
            portID: portID
        )

        // Notify the background script's onConnect listeners
        let escapedName = name.jsEscapedForSingleQuotes
        let js = "if (window.__extensionDispatchConnect) { window.__extensionDispatchConnect('\(portID)', '\(escapedName)'); }"
        backgroundHost.evaluateJavaScript(js)
    }

    private func handlePortPostMessage(body: [String: Any], extensionID: String, sourceWebView: WKWebView?) {
        guard let portID = body["portID"] as? String,
              let message = body["message"],
              let port = openPorts[portID] else { return }

        guard let messageData = try? JSONSerialization.data(withJSONObject: message),
              let messageJSON = String(data: messageData, encoding: .utf8) else { return }

        // Route to the other end of the port
        let targetWebView: WKWebView?
        let targetWorld: WKContentWorld
        if sourceWebView === port.sourceWebView {
            targetWebView = port.targetWebView
            targetWorld = port.targetContentWorld
        } else {
            targetWebView = port.sourceWebView
            targetWorld = port.sourceContentWorld
        }

        let js = "if (window.__extensionDispatchPortMessage) { window.__extensionDispatchPortMessage('\(portID)', \(messageJSON)); }"
        if targetWorld == .page {
            targetWebView?.evaluateJavaScript(js) { _, _ in }
        } else {
            targetWebView?.evaluateJavaScript(js, in: nil, in: targetWorld) { _ in }
        }
    }

    private func handlePortDisconnect(body: [String: Any], extensionID: String) {
        guard let portID = body["portID"] as? String,
              let port = openPorts.removeValue(forKey: portID) else { return }

        // Notify the other end
        let js = "if (window.__extensionDispatchPortDisconnect) { window.__extensionDispatchPortDisconnect('\(portID)'); }"

        // Notify both ends (the disconnect call came from one side)
        let targetWorld = port.targetContentWorld
        if targetWorld == .page {
            port.targetWebView?.evaluateJavaScript(js) { _, _ in }
        } else {
            port.targetWebView?.evaluateJavaScript(js, in: nil, in: targetWorld) { _ in }
        }
    }

    // MARK: - Storage Changed Broadcast

    private func broadcastStorageChanged(changes: [String: Any], areaName: String, extensionID: String, sourceWebView: WKWebView? = nil, isContentScript: Bool = true) {
        guard let changesData = try? JSONSerialization.data(withJSONObject: changes),
              let changesJSON = String(data: changesData, encoding: .utf8) else { return }

        let escapedArea = areaName.jsEscapedForSingleQuotes
        let js = "if (window.__extensionDispatchStorageChanged) { window.__extensionDispatchStorageChanged(\(changesJSON), '\(escapedArea)'); }"

        // Dispatch to the extension's background host
        let bgWebView = ExtensionManager.shared.backgroundHost(for: extensionID)?.webView
        bgWebView?.evaluateJavaScript(js) { _, _ in }

        // Dispatch to the source webView (popup or other context) if it's not the background
        if let sourceWebView, sourceWebView !== bgWebView {
            if isContentScript, let ext = ExtensionManager.shared.extension(withID: extensionID) {
                sourceWebView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
            } else {
                sourceWebView.evaluateJavaScript(js) { _, _ in }
            }
        }

        // Dispatch to all tabs with the extension's content scripts
        guard let ext = ExtensionManager.shared.extension(withID: extensionID) else { return }
        for space in TabStore.shared.spaces {
            // Chrome's storage.local doesn't cross the incognito boundary
            if space.isIncognito { continue }

            for tab in space.tabs {
                if tab.webView !== sourceWebView {
                    tab.webView?.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
                }
            }
            // Also broadcast to live pinned tabs
            for entry in space.pinnedEntries {
                if let wv = entry.tab?.webView, wv !== sourceWebView {
                    wv.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
                }
            }
        }
    }

    private func deliverCallbackResponse(callbackID: String, result: String, extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        let escaped = result.jsEscapedForSingleQuotes
        deliverJS("window.__extensionDeliverResponse('\(callbackID)', '\(escaped)');",
                  extensionID: extensionID, webView: webView, isContentScript: isContentScript)
    }

    private func deliverCallbackResponse(callbackID: String, result: Bool, extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        deliverJS("window.__extensionDeliverResponse('\(callbackID)', \(result ? "true" : "false"));",
                  extensionID: extensionID, webView: webView, isContentScript: isContentScript)
    }

    // MARK: - Tab Lookup Helpers

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

    /// Find a tab by its WKWebView reference.
    private func findTabByWebView(_ webView: WKWebView) -> (BrowserTab, Space)? {
        for space in TabStore.shared.spaces {
            for tab in space.tabs {
                if tab.webView === webView { return (tab, space) }
            }
            for entry in space.pinnedEntries {
                guard let tab = entry.tab else { continue }
                if tab.webView === webView { return (tab, space) }
            }
        }
        return nil
    }

    // MARK: - Runtime: openOptionsPage

    private func handleRuntimeOpenOptionsPage(ctx: MessageContext?, body: [String: Any]) {
        let extensionID = ctx?.extensionID ?? (body["extensionID"] as? String ?? "")

        guard let ext = ExtensionManager.shared.extension(withID: extensionID),
              ext.optionsURL != nil else {
            if let ctx {
                deliverResponse(ctx, result: ["__error": "No options page defined"])
            }
            return
        }

        NotificationCenter.default.post(
            name: ExtensionManager.openOptionsPageNotification,
            object: nil,
            userInfo: ["extensionID": extensionID]
        )

        if let ctx {
            deliverResponse(ctx, result: [:] as [String: Any])
        }
    }

    // MARK: - Resource: get (content script resource loading)

    private func handleResourceGet(ctx: MessageContext?, body: [String: Any]) {
        let extensionID = ctx?.extensionID ?? (body["extensionID"] as? String ?? "")
        let path = body["path"] as? String ?? ""

        guard let ext = ExtensionManager.shared.extension(withID: extensionID),
              !path.isEmpty else {
            if let ctx {
                deliverResponse(ctx, result: ["__error": "Not found"])
            }
            return
        }

        let fileURL = ext.basePath.appendingPathComponent(path)

        // Security: ensure the path is within the extension's base directory
        let resolvedPath = fileURL.standardizedFileURL.path
        let basePath = ext.basePath.standardizedFileURL.path
        guard resolvedPath.hasPrefix(basePath),
              let data = try? String(contentsOf: fileURL, encoding: .utf8) else {
            if let ctx {
                deliverResponse(ctx, result: ["__error": "Not found"])
            }
            return
        }

        let mimeType = ExtensionPageSchemeHandler.mimeType(for: fileURL)
        if let ctx {
            deliverResponse(ctx, result: ["data": data, "mimeType": mimeType])
        }
    }

    private func deliverCallbackResponse(callbackID: String, result: [[String: Any]], extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        guard let resultData = try? JSONSerialization.data(withJSONObject: result),
              let resultJSON = String(data: resultData, encoding: .utf8) else { return }
        deliverJS("window.__extensionDeliverResponse('\(callbackID)', \(resultJSON));",
                  extensionID: extensionID, webView: webView, isContentScript: isContentScript)
    }

    // MARK: - Action Handlers

    private func handleActionSetIcon(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        // Store custom icon if path provided
        if let path = params["path"] as? String,
           let ext = ExtensionManager.shared.extension(withID: ctx.extensionID) {
            let iconURL = ext.basePath.appendingPathComponent(path)
            if let image = NSImage(contentsOf: iconURL) {
                ExtensionManager.shared.customIcons[ctx.extensionID] = image
            }
        } else if let iconDict = params["path"] as? [String: String],
                  let ext = ExtensionManager.shared.extension(withID: ctx.extensionID) {
            // Sized icon dict — pick best
            let bestPath = iconDict["32"] ?? iconDict["48"] ?? iconDict["16"] ?? iconDict.values.first
            if let bp = bestPath {
                let iconURL = ext.basePath.appendingPathComponent(bp)
                if let image = NSImage(contentsOf: iconURL) {
                    ExtensionManager.shared.customIcons[ctx.extensionID] = image
                }
            }
        }

        NotificationCenter.default.post(name: ExtensionManager.extensionActionDidChangeNotification, object: nil,
                                        userInfo: ["extensionID": ctx.extensionID])
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleActionSetBadgeText(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        let text = params["text"] as? String ?? ""
        let oldText = ExtensionManager.shared.badgeText[ctx.extensionID] ?? ""
        ExtensionManager.shared.badgeText[ctx.extensionID] = text
        if text != oldText {
            NotificationCenter.default.post(name: ExtensionManager.extensionActionDidChangeNotification, object: nil,
                                            userInfo: ["extensionID": ctx.extensionID])
        }
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleActionSetBadgeBackgroundColor(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        let oldColor = ExtensionManager.shared.badgeBackgroundColor[ctx.extensionID]
        if let colorArray = params["color"] as? [Int], colorArray.count >= 3 {
            let r = CGFloat(colorArray[0]) / 255.0
            let g = CGFloat(colorArray[1]) / 255.0
            let b = CGFloat(colorArray[2]) / 255.0
            let a = colorArray.count >= 4 ? CGFloat(colorArray[3]) / 255.0 : 1.0
            ExtensionManager.shared.badgeBackgroundColor[ctx.extensionID] = NSColor(red: r, green: g, blue: b, alpha: a)
        } else if let colorString = params["color"] as? String {
            ExtensionManager.shared.badgeBackgroundColor[ctx.extensionID] = NSColor(hex: colorString)
        }

        let newColor = ExtensionManager.shared.badgeBackgroundColor[ctx.extensionID]
        if oldColor != newColor {
            NotificationCenter.default.post(name: ExtensionManager.extensionActionDidChangeNotification, object: nil,
                                            userInfo: ["extensionID": ctx.extensionID])
        }
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleActionGetBadgeText(ctx: MessageContext, body: [String: Any]) {
        let text = ExtensionManager.shared.badgeText[ctx.extensionID] ?? ""
        deliverResponse(ctx, result: text)
    }

    private func handleActionSetTitle(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        if let title = params["title"] as? String {
            let oldTitle = ExtensionManager.shared.actionTitle[ctx.extensionID]
            ExtensionManager.shared.actionTitle[ctx.extensionID] = title
            if title != oldTitle {
                NotificationCenter.default.post(name: ExtensionManager.extensionActionDidChangeNotification, object: nil,
                                                userInfo: ["extensionID": ctx.extensionID])
            }
        }
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    private func handleActionGetTitle(ctx: MessageContext, body: [String: Any]) {
        let title = ExtensionManager.shared.actionTitle[ctx.extensionID] ?? ""
        deliverResponse(ctx, result: title)
    }

    private func handleActionSetPopup(ctx: MessageContext, body: [String: Any]) {
        // Store but don't actively use yet (popup URL override)
        deliverResponse(ctx, result: [:] as [String: Any])
    }

    // MARK: - Commands Handlers

    private func handleCommandsGetAll(ctx: MessageContext, body: [String: Any]) {
        guard let ext = ExtensionManager.shared.extension(withID: ctx.extensionID) else {
            deliverResponse(ctx, result: [] as [[String: Any]])
            return
        }

        var commands: [[String: Any]] = []
        if let manifestCommands = ext.manifest.commands {
            for (name, cmd) in manifestCommands {
                var cmdInfo: [String: Any] = ["name": name]
                if let desc = cmd.description { cmdInfo["description"] = desc }
                let shortcut = cmd.suggestedKey?.mac ?? cmd.suggestedKey?.default ?? ""
                cmdInfo["shortcut"] = shortcut
                commands.append(cmdInfo)
            }
        }

        deliverResponse(ctx, result: commands)
    }

    // MARK: - Window Info Builder

    private func buildWindowInfo(space: Space, focused: Bool) -> [String: Any] {
        let windowID = ExtensionManager.shared.spaceIDMap.intID(for: space.id)
        return [
            "id": windowID,
            "focused": focused,
            "type": "normal",
            "state": "normal",
            "incognito": space.isIncognito
        ]
    }

    // MARK: - Windows Handlers

    private func handleWindowsGetAll(ctx: MessageContext, body: [String: Any]) {
        let mgr = ExtensionManager.shared
        var windows: [[String: Any]] = []

        for space in TabStore.shared.spaces {
            if space.isIncognito { continue }
            var windowInfo = buildWindowInfo(space: space, focused: space.id == mgr.lastActiveSpaceID)

            let params = body["params"] as? [String: Any] ?? [:]
            let queryOptions = params["queryOptions"] as? [String: Any] ?? [:]
            if queryOptions["populate"] as? Bool == true {
                let ext = mgr.extension(withID: ctx.extensionID)
                let includeURLFields = ext.map { ExtensionPermissionChecker.hasPermission("tabs", extension: $0) } ?? true
                var tabs: [[String: Any]] = []
                for tab in space.tabs {
                    let isActive = space.selectedTabID == tab.id
                    tabs.append(buildTabInfo(tab: tab, space: space, isActive: isActive, includeURLFields: includeURLFields, extension: ext))
                }
                windowInfo["tabs"] = tabs
            }

            windows.append(windowInfo)
        }

        deliverResponse(ctx, result: windows)
    }

    private func handleWindowsGet(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any] else { return }

        let windowId = params["windowId"] as? Int
        let mgr = ExtensionManager.shared

        if let windowId, let spaceUUID = mgr.spaceIDMap.uuid(for: windowId),
           let space = TabStore.shared.space(withID: spaceUUID) {
            let windowInfo = buildWindowInfo(space: space, focused: space.id == mgr.lastActiveSpaceID)
            deliverResponse(ctx, result: windowInfo)
        } else {
            deliverResponse(ctx, result: ["__error": "Window not found"])
        }
    }

    private func handleWindowsGetCurrent(ctx: MessageContext, body: [String: Any]) {
        let mgr = ExtensionManager.shared
        if let activeSpaceID = mgr.lastActiveSpaceID,
           let space = TabStore.shared.space(withID: activeSpaceID) {
            let windowInfo = buildWindowInfo(space: space, focused: true)
            deliverResponse(ctx, result: windowInfo)
        } else {
            deliverResponse(ctx, result: ["__error": "No current window"])
        }
    }

    private func handleWindowsCreate(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]
        let createData = params["createData"] as? [String: Any] ?? [:]

        // Create a new space to represent the window
        let url = (createData["url"] as? String).flatMap { URL(string: $0) }
        // Use the default profile from the current active space
        let profileID: UUID
        if let activeSpaceID = ExtensionManager.shared.lastActiveSpaceID,
           let activeSpace = TabStore.shared.space(withID: activeSpaceID) {
            profileID = activeSpace.profileID
        } else if let first = TabStore.shared.spaces.first {
            profileID = first.profileID
        } else {
            deliverResponse(ctx, result: ["__error": "No profile available"])
            return
        }
        let space = TabStore.shared.addSpace(name: "Window", emoji: "🌐", colorHex: "#333333", profileID: profileID)
        if let url {
            TabStore.shared.addTab(in: space, url: url)
        }

        let windowInfo = buildWindowInfo(space: space, focused: true)
        deliverResponse(ctx, result: windowInfo)
    }

    private func handleWindowsUpdate(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any] else { return }

        let windowId = params["windowId"] as? Int
        let mgr = ExtensionManager.shared

        if let windowId, let spaceUUID = mgr.spaceIDMap.uuid(for: windowId),
           let space = TabStore.shared.space(withID: spaceUUID) {
            // updateInfo like focused, state etc. — we handle focused
            let updateInfo = params["updateInfo"] as? [String: Any] ?? [:]
            if updateInfo["focused"] as? Bool == true {
                mgr.lastActiveSpaceID = space.id
            }

            let windowInfo = buildWindowInfo(space: space, focused: space.id == mgr.lastActiveSpaceID)
            deliverResponse(ctx, result: windowInfo)
        } else {
            deliverResponse(ctx, result: ["__error": "Window not found"])
        }
    }

    // MARK: - Font Settings Handlers

    private func handleFontSettingsGetFontList(ctx: MessageContext, body: [String: Any]) {
        let fontFamilies = NSFontManager.shared.availableFontFamilies
        let fontList = fontFamilies.map { family -> [String: String] in
            ["fontId": family, "displayName": family]
        }

        guard let resultData = try? JSONSerialization.data(withJSONObject: fontList),
              let resultJSON = String(data: resultData, encoding: .utf8) else { return }
        deliverJS("window.__extensionDeliverResponse('\(ctx.callbackID)', \(resultJSON));",
                  extensionID: ctx.extensionID, webView: ctx.sourceWebView, isContentScript: ctx.isContentScript)
    }

    // MARK: - Permissions Handlers

    private func handlePermissionsContains(ctx: MessageContext, body: [String: Any]) {
        guard let params = body["params"] as? [String: Any],
              let permissions = params["permissions"] as? [String: Any] else { return }

        guard let ext = ExtensionManager.shared.extension(withID: ctx.extensionID) else {
            deliverResponse(ctx, result: false)
            return
        }

        // Check all requested permissions
        let requestedPerms = permissions["permissions"] as? [String] ?? []
        let requestedOrigins = permissions["origins"] as? [String] ?? []

        var hasAll = true
        for perm in requestedPerms {
            if !ExtensionPermissionChecker.hasPermission(perm, extension: ext) {
                hasAll = false
                break
            }
        }

        if hasAll {
            for origin in requestedOrigins {
                if let url = URL(string: origin.replacingOccurrences(of: "*", with: "example.com")) {
                    if !ExtensionPermissionChecker.hasHostPermission(for: url, extension: ext) {
                        hasAll = false
                        break
                    }
                }
            }
        }

        deliverResponse(ctx, result: hasAll)
    }

    // MARK: - Runtime: setUninstallURL

    private func handleRuntimeSetUninstallURL(ctx: MessageContext, body: [String: Any]) {
        let params = body["params"] as? [String: Any] ?? [:]

        if let urlString = params["url"] as? String, let url = URL(string: urlString) {
            ExtensionManager.shared.uninstallURLs[ctx.extensionID] = url
        }

        deliverResponse(ctx, result: [:] as [String: Any])
    }

    // MARK: - JS Delivery

    private func deliverJS(_ js: String, extensionID: String, webView: WKWebView?, isContentScript: Bool) {
        guard let webView else { return }
        if isContentScript, let ext = ExtensionManager.shared.extension(withID: extensionID) {
            webView.evaluateJavaScript(js, in: nil, in: ext.contentWorld) { _ in }
        } else {
            webView.evaluateJavaScript(js) { _, _ in }
        }
    }
}
