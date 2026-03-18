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

            function makeEventEmitter(listeners) {
                return {
                    addListener: function(cb) { listeners.push(cb); },
                    removeListener: function(cb) {
                        var idx = listeners.indexOf(cb);
                        if (idx !== -1) listeners.splice(idx, 1);
                    },
                    hasListener: function(cb) { return listeners.includes(cb); }
                };
            }

            chrome.webNavigation.onBeforeNavigate = makeEventEmitter(onBeforeNavigateListeners);
            chrome.webNavigation.onCommitted = makeEventEmitter(onCommittedListeners);
            chrome.webNavigation.onCompleted = makeEventEmitter(onCompletedListeners);
            chrome.webNavigation.onErrorOccurred = makeEventEmitter(onErrorOccurredListeners);

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
