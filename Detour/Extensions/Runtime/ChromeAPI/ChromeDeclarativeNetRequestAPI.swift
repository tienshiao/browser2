import Foundation

/// Generates the `chrome.declarativeNetRequest` polyfill JavaScript.
/// This is a stub implementation that provides the API surface without actual rule enforcement.
struct ChromeDeclarativeNetRequestAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.declarativeNetRequest) window.chrome.declarativeNetRequest = {};

            var dnr = chrome.declarativeNetRequest;

            // Constants
            dnr.MAX_NUMBER_OF_REGEX_RULES = 1000;
            dnr.MAX_NUMBER_OF_STATIC_RULESETS = 100;
            dnr.MAX_NUMBER_OF_ENABLED_STATIC_RULESETS = 50;
            dnr.MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES = 5000;
            dnr.DYNAMIC_RULESET_ID = '_dynamic';
            dnr.SESSION_RULESET_ID = '_session';
            dnr.GUARANTEED_MINIMUM_STATIC_RULES = 30000;

            dnr.getDynamicRules = function(callback) {
                var result = [];
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            dnr.getSessionRules = function(callback) {
                var result = [];
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            dnr.updateDynamicRules = function(options, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            dnr.updateSessionRules = function(options, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            dnr.updateEnabledRulesets = function(options, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            dnr.getEnabledRulesets = function(callback) {
                var result = [];
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            dnr.getAvailableStaticRuleCount = function(callback) {
                var result = 30000;
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            dnr.isRegexSupported = function(regexOptions, callback) {
                var result = { isSupported: true };
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            dnr.getMatchedRules = function(filter, callback) {
                if (typeof filter === 'function') {
                    callback = filter;
                    filter = null;
                }
                var result = { rulesMatchedInfo: [] };
                if (callback) { callback(result); return; }
                return Promise.resolve(result);
            };

            dnr.setExtensionActionOptions = function(options, callback) {
                if (callback) { callback(); return; }
                return Promise.resolve();
            };

            var _onRuleMatchedDebugListeners = [];
            dnr.onRuleMatchedDebug = __detourMakeEventEmitter(_onRuleMatchedDebugListeners);
        })();
        """
    }
}
