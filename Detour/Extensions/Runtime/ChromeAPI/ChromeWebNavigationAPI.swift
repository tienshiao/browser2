import Foundation

/// Generates the `chrome.webNavigation` polyfill JavaScript for a given extension.
struct ChromeWebNavigationAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.webNavigation) window.chrome.webNavigation = {};

            var onBeforeNavigateListeners = [];
            var onCommittedListeners = [];
            var onCompletedListeners = [];
            var onErrorOccurredListeners = [];

            chrome.webNavigation.onBeforeNavigate = __detourMakeEventEmitter(onBeforeNavigateListeners);
            chrome.webNavigation.onCommitted = __detourMakeEventEmitter(onCommittedListeners);
            chrome.webNavigation.onCompleted = __detourMakeEventEmitter(onCompletedListeners);
            chrome.webNavigation.onErrorOccurred = __detourMakeEventEmitter(onErrorOccurredListeners);

            // Internal: called by native bridge to dispatch webNavigation events
            window.__extensionDispatchWebNavEvent = function(eventName, details) {
                var listeners;
                switch (eventName) {
                    case 'onBeforeNavigate': listeners = onBeforeNavigateListeners; break;
                    case 'onCommitted': listeners = onCommittedListeners; break;
                    case 'onCompleted': listeners = onCompletedListeners; break;
                    case 'onErrorOccurred': listeners = onErrorOccurredListeners; break;
                    default: return;
                }
                for (var i = 0; i < listeners.length; i++) {
                    try {
                        listeners[i](details);
                    } catch (e) {
                        console.error('[chrome.webNavigation.' + eventName + '] listener error:', e);
                    }
                }
            };
        })();
        """
    }
}
