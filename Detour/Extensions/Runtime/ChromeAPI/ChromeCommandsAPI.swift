import Foundation

/// Generates the `chrome.commands` polyfill JavaScript for a given extension.
struct ChromeCommandsAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.commands) window.chrome.commands = {};

            const extensionID = '\(extensionID)';
            const onCommandListeners = [];

            chrome.commands.getAll = function(callback) {
                return new Promise(function(resolve, reject) {
                    const callbackID = 'commands_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

                    if (!window.__extensionCallbacks) window.__extensionCallbacks = {};
                    window.__extensionCallbacks[callbackID] = function(result) {
                        delete window.__extensionCallbacks[callbackID];
                        if (result && result.__error) {
                            reject(new Error(result.__error));
                        } else {
                            const commands = Array.isArray(result) ? result : [];
                            if (callback) callback(commands);
                            resolve(commands);
                        }
                    };

                    window.webkit.messageHandlers.extensionMessage.postMessage({
                        extensionID: extensionID,
                        type: 'commands.getAll',
                        params: {},
                        callbackID: callbackID,
                        isContentScript: \(isContentScript ? "true" : "false")
                    });
                });
            };

            chrome.commands.onCommand = __detourMakeEventEmitter(onCommandListeners);

            // Internal: called by native bridge to dispatch command events
            window.__extensionDispatchCommand = function(commandName) {
                for (let i = 0; i < onCommandListeners.length; i++) {
                    try { onCommandListeners[i](commandName); } catch(e) {
                        console.error('[chrome.commands.onCommand] listener error:', e);
                    }
                }
            };
        })();
        """
    }
}
