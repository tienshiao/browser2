import Foundation

/// Generates the `chrome.notifications` polyfill JavaScript for a given extension.
struct ChromeNotificationsAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.notifications) window.chrome.notifications = {};

            const extensionID = '\(extensionID)';

            function notifRequest(action, params) {
                return new Promise(function(resolve, reject) {
                    const callbackID = 'notif_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
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
                        type: 'notifications.' + action,
                        params: params || {},
                        callbackID: callbackID,
                        isContentScript: \(isContentScript ? "true" : "false")
                    });
                });
            }

            chrome.notifications.create = function(notificationId, options, callback) {
                if (typeof notificationId === 'object') {
                    callback = options;
                    options = notificationId;
                    notificationId = null;
                }
                var promise = notifRequest('create', { notificationId: notificationId, options: options || {} });
                if (callback) { promise.then(function(r) { callback(r.notificationId || ''); }); return; }
                return promise.then(function(r) { return r.notificationId || ''; });
            };

            chrome.notifications.update = function(notificationId, options, callback) {
                var promise = notifRequest('update', { notificationId: notificationId, options: options || {} });
                if (callback) { promise.then(function(r) { callback(r.wasUpdated === true); }); return; }
                return promise.then(function(r) { return r.wasUpdated === true; });
            };

            chrome.notifications.clear = function(notificationId, callback) {
                var promise = notifRequest('clear', { notificationId: notificationId });
                if (callback) { promise.then(function(r) { callback(r.wasCleared === true); }); return; }
                return promise.then(function(r) { return r.wasCleared === true; });
            };

            chrome.notifications.getAll = function(callback) {
                var promise = notifRequest('getAll', {});
                if (callback) { promise.then(callback); return; }
                return promise;
            };

            var _onClickedListeners = [];
            var _onButtonClickedListeners = [];
            var _onClosedListeners = [];

            chrome.notifications.onClicked = __detourMakeEventEmitter(_onClickedListeners);
            chrome.notifications.onButtonClicked = __detourMakeEventEmitter(_onButtonClickedListeners);
            chrome.notifications.onClosed = __detourMakeEventEmitter(_onClosedListeners);

            window.__extensionDispatchNotificationClicked = function(notificationId) {
                for (var i = 0; i < _onClickedListeners.length; i++) {
                    try { _onClickedListeners[i](notificationId); } catch(e) {}
                }
            };

            window.__extensionDispatchNotificationButtonClicked = function(notificationId, buttonIndex) {
                for (var i = 0; i < _onButtonClickedListeners.length; i++) {
                    try { _onButtonClickedListeners[i](notificationId, buttonIndex); } catch(e) {}
                }
            };

            window.__extensionDispatchNotificationClosed = function(notificationId, byUser) {
                for (var i = 0; i < _onClosedListeners.length; i++) {
                    try { _onClosedListeners[i](notificationId, byUser); } catch(e) {}
                }
            };
        })();
        """
    }
}
