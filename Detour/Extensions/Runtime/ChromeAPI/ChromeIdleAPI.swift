import Foundation

/// Generates the `chrome.idle` polyfill JavaScript for a given extension.
struct ChromeIdleAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.idle) window.chrome.idle = {};

            const extensionID = '\(extensionID)';

            chrome.idle.queryState = function(detectionIntervalInSeconds, callback) {
                return new Promise(function(resolve, reject) {
                    const callbackID = 'idle_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                    if (!window.__extensionCallbacks) window.__extensionCallbacks = {};
                    window.__extensionCallbacks[callbackID] = function(result) {
                        delete window.__extensionCallbacks[callbackID];
                        if (result && result.__error) {
                            reject(new Error(result.__error));
                        } else {
                            var state = (typeof result === 'string') ? result : 'active';
                            if (callback) callback(state);
                            resolve(state);
                        }
                    };
                    window.webkit.messageHandlers.extensionMessage.postMessage({
                        extensionID: extensionID,
                        type: 'idle.queryState',
                        params: { detectionIntervalInSeconds: detectionIntervalInSeconds },
                        callbackID: callbackID,
                        isContentScript: \(isContentScript ? "true" : "false")
                    });
                });
            };

            chrome.idle.setDetectionInterval = function(intervalInSeconds) {
                window.webkit.messageHandlers.extensionMessage.postMessage({
                    extensionID: extensionID,
                    type: 'idle.setDetectionInterval',
                    params: { intervalInSeconds: intervalInSeconds },
                    isContentScript: \(isContentScript ? "true" : "false")
                });
            };

            var onStateChangedListeners = [];
            chrome.idle.onStateChanged = __detourMakeEventEmitter(onStateChangedListeners);

            window.__extensionDispatchIdleStateChanged = function(newState) {
                for (var i = 0; i < onStateChangedListeners.length; i++) {
                    try { onStateChangedListeners[i](newState); } catch(e) {
                        console.error('[chrome.idle.onStateChanged] listener error:', e);
                    }
                }
            };

            chrome.idle.IdleState = { ACTIVE: 'active', IDLE: 'idle', LOCKED: 'locked' };
        })();
        """
    }
}
