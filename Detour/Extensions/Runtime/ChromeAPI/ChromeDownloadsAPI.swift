import Foundation

/// Generates the `chrome.downloads` polyfill JavaScript for a given extension.
struct ChromeDownloadsAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.downloads) window.chrome.downloads = {};

            const extensionID = '\(extensionID)';

            function downloadsRequest(action, params) {
                return new Promise(function(resolve, reject) {
                    const callbackID = 'dl_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
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
                        type: 'downloads.' + action,
                        params: params || {},
                        callbackID: callbackID,
                        isContentScript: \(isContentScript ? "true" : "false")
                    });
                });
            }

            chrome.downloads.download = function(options, callback) {
                var promise = downloadsRequest('download', { options: options || {} });
                if (callback) { promise.then(function(r) { callback(r.downloadId || 0); }); return; }
                return promise.then(function(r) { return r.downloadId || 0; });
            };

            chrome.downloads.search = function(query, callback) {
                var result = [];
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            chrome.downloads.pause = function(downloadId, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            chrome.downloads.resume = function(downloadId, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            chrome.downloads.cancel = function(downloadId, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            chrome.downloads.open = function(downloadId, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            chrome.downloads.show = function(downloadId) {
                // No-op
            };

            chrome.downloads.erase = function(query, callback) {
                var result = [];
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            var _onChangedListeners = [];
            var _onCreatedListeners = [];
            var _onDeterminingFilenameListeners = [];

            chrome.downloads.onChanged = __detourMakeEventEmitter(_onChangedListeners);
            chrome.downloads.onCreated = __detourMakeEventEmitter(_onCreatedListeners);
            chrome.downloads.onDeterminingFilename = __detourMakeEventEmitter(_onDeterminingFilenameListeners);
        })();
        """
    }
}
