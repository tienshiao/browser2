import Foundation

/// Generates the `chrome.scripting` polyfill JavaScript for a given extension.
struct ChromeScriptingAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.scripting) window.chrome.scripting = {};

            const extensionID = '\(extensionID)';

            function scriptingRequest(action, params) {
                return new Promise(function(resolve, reject) {
                    const callbackID = 'scripting_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

                    if (!window.__extensionCallbacks) window.__extensionCallbacks = {};
                    window.__extensionCallbacks[callbackID] = function(result) {
                        delete window.__extensionCallbacks[callbackID];
                        if (result && result.__error) {
                            reject(new Error(result.__error));
                        } else {
                            resolve(result);
                        }
                    };

                    window.webkit.messageHandlers.extensionMessage.postMessage({
                        extensionID: extensionID,
                        type: 'scripting.' + action,
                        params: params || {},
                        callbackID: callbackID,
                        isContentScript: \(isContentScript ? "true" : "false")
                    });
                });
            }

            chrome.scripting.executeScript = function(injection, callback) {
                const promise = scriptingRequest('executeScript', { injection: injection });
                if (callback) { promise.then(callback); return; }
                return promise;
            };

            chrome.scripting.insertCSS = function(injection, callback) {
                const promise = scriptingRequest('insertCSS', { injection: injection });
                if (callback) { promise.then(callback); return; }
                return promise;
            };

            chrome.scripting.removeCSS = function(injection, callback) {
                // No-op stub — WebKit doesn't support targeted CSS removal
                const promise = Promise.resolve();
                if (callback) { promise.then(callback); return; }
                return promise;
            };
        })();
        """
    }
}
