import Foundation
import WebKit

/// Relays CustomEvents from the page world (MAIN) to extension content worlds (ISOLATED).
///
/// WKWebKit content worlds have separate JS namespaces — custom events dispatched in
/// one world's Document wrapper don't reach listeners in another world. Chrome doesn't
/// have this limitation (ISOLATED and MAIN share the DOM event system).
///
/// The complementary direction (content world → page world) is handled by inline
/// `<script>` element injection in `ContentScriptInjector`.
class EventRelayHandler: NSObject, WKScriptMessageHandler {
    static let shared = EventRelayHandler()
    static let handlerName = "extensionEventRelay"

    /// Content worlds to relay events into.
    private var contentWorlds: [WKContentWorld] = []

    private override init() {
        super.init()
    }

    /// Register the relay on a WKUserContentController for a given extension content world.
    /// The handler is registered in the `.page` world so page-world scripts can post to it.
    func register(on controller: WKUserContentController, contentWorld: WKContentWorld) {
        if !contentWorlds.contains(where: { $0 === contentWorld }) {
            contentWorlds.append(contentWorld)
        }
        controller.add(self, contentWorld: .page, name: Self.handlerName)
    }

    /// Remove a content world (e.g. when an extension is disabled).
    func unregister(contentWorld: WKContentWorld) {
        contentWorlds.removeAll { $0 === contentWorld }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let webView = message.webView else { return }

        let detailJSON: String
        if let detail = body["detail"] {
            // JSONSerialization.data(withJSONObject:) throws an NSException (not a Swift
            // error) for non-collection top-level types like strings, numbers, booleans.
            // Handle primitives explicitly to avoid a crash.
            if detail is String || detail is NSNumber || detail is Bool {
                if let data = try? JSONSerialization.data(withJSONObject: [detail]),
                   let arr = String(data: data, encoding: .utf8) {
                    // Unwrap from the array wrapper: "[value]" → "value"
                    let start = arr.index(after: arr.startIndex)
                    let end = arr.index(before: arr.endIndex)
                    detailJSON = String(arr[start..<end])
                } else {
                    detailJSON = "null"
                }
            } else if JSONSerialization.isValidJSONObject(detail) {
                if let data = try? JSONSerialization.data(withJSONObject: detail),
                   let str = String(data: data, encoding: .utf8) {
                    detailJSON = str
                } else {
                    detailJSON = "null"
                }
            } else {
                detailJSON = "null"
            }
        } else {
            detailJSON = "null"
        }

        let escapedType = type.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        // Pass the target element's relay ID so the content world can dispatch
        // the event on the correct DOM element (not just on document).
        let targetRelayId = body["targetRelayId"] as? String
        let targetArg: String
        if let id = targetRelayId {
            let escapedId = id.replacingOccurrences(of: "'", with: "\\'")
            targetArg = "'\(escapedId)'"
        } else {
            targetArg = "null"
        }

        let js = "if (window.__detourDispatchRelayedEvent) { window.__detourDispatchRelayedEvent('\(escapedType)', \(detailJSON), \(targetArg)); }"

        for world in contentWorlds {
            webView.evaluateJavaScript(js, in: nil, in: world) { _ in }
        }
    }
}
