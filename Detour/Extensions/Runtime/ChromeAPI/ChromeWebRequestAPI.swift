import Foundation

/// Generates the `chrome.webRequest` stub JavaScript.
/// WebKit provides no pre-request interception API, so these are no-op event emitters
/// that accept listeners but never fire them.
struct ChromeWebRequestAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.webRequest) window.chrome.webRequest = {};

            function makeNoOpEventEmitter(name) {
                var warned = false;
                return {
                    addListener: function(cb, filter, extraInfoSpec) {
                        if (!warned) {
                            console.warn('[Detour] chrome.webRequest.' + name +
                                ' is a no-op stub. WebKit does not support request interception.');
                            warned = true;
                        }
                    },
                    removeListener: function(cb) {},
                    hasListener: function(cb) { return false; }
                };
            }

            chrome.webRequest.onBeforeRequest = makeNoOpEventEmitter('onBeforeRequest');
            chrome.webRequest.onBeforeSendHeaders = makeNoOpEventEmitter('onBeforeSendHeaders');
            chrome.webRequest.onSendHeaders = makeNoOpEventEmitter('onSendHeaders');
            chrome.webRequest.onHeadersReceived = makeNoOpEventEmitter('onHeadersReceived');
            chrome.webRequest.onAuthRequired = makeNoOpEventEmitter('onAuthRequired');
            chrome.webRequest.onResponseStarted = makeNoOpEventEmitter('onResponseStarted');
            chrome.webRequest.onBeforeRedirect = makeNoOpEventEmitter('onBeforeRedirect');
            chrome.webRequest.onCompleted = makeNoOpEventEmitter('onCompleted');
            chrome.webRequest.onErrorOccurred = makeNoOpEventEmitter('onErrorOccurred');
        })();
        """
    }
}
