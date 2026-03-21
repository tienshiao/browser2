import Foundation

/// Generates the `chrome.management` polyfill JavaScript for a given extension.
struct ChromeManagementAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.management) window.chrome.management = {};

            const extensionID = '\(extensionID)';

            function mgmtRequest(action, params) {
                return new Promise(function(resolve, reject) {
                    const callbackID = 'mgmt_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
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
                        type: 'management.' + action,
                        params: params || {},
                        callbackID: callbackID,
                        isContentScript: \(isContentScript ? "true" : "false")
                    });
                });
            }

            chrome.management.getSelf = function(callback) {
                var promise = mgmtRequest('getSelf', {});
                if (callback) { promise.then(callback); return; }
                return promise;
            };

            chrome.management.getAll = function(callback) {
                var promise = mgmtRequest('getAll', {});
                if (callback) { promise.then(callback); return; }
                return promise;
            };

            chrome.management.setEnabled = function(id, enabled, callback) {
                var promise = mgmtRequest('setEnabled', { id: id, enabled: enabled });
                if (callback) { promise.then(function() { callback(); }); return; }
                return promise;
            };

            var _onEnabledListeners = [];
            var _onDisabledListeners = [];
            var _onInstalledListeners = [];
            var _onUninstalledListeners = [];

            chrome.management.onEnabled = __detourMakeEventEmitter(_onEnabledListeners);
            chrome.management.onDisabled = __detourMakeEventEmitter(_onDisabledListeners);
            chrome.management.onInstalled = __detourMakeEventEmitter(_onInstalledListeners);
            chrome.management.onUninstalled = __detourMakeEventEmitter(_onUninstalledListeners);
        })();
        """
    }
}
