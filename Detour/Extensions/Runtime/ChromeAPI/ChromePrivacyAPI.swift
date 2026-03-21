import Foundation

/// Generates the `chrome.privacy` polyfill JavaScript.
/// All settings are read-only stubs — `set()` and `clear()` are no-ops.
struct ChromePrivacyAPI {
    static func generateJS(extensionID: String, isContentScript: Bool = true) -> String {
        return """
        (function() {
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.privacy) window.chrome.privacy = {};
            if (!window.chrome.privacy.services) window.chrome.privacy.services = {};
            if (!window.chrome.privacy.network) window.chrome.privacy.network = {};
            if (!window.chrome.privacy.websites) window.chrome.privacy.websites = {};

            function makeSetting(defaultValue) {
                return {
                    get: function(details, callback) {
                        var result = { value: defaultValue, levelOfControl: 'not_controllable' };
                        if (callback) { callback(result); return; }
                        return Promise.resolve(result);
                    },
                    set: function(details, callback) {
                        if (callback) { callback(); return; }
                        return Promise.resolve();
                    },
                    clear: function(details, callback) {
                        if (callback) { callback(); return; }
                        return Promise.resolve();
                    },
                    onChange: __detourMakeEventEmitter([])
                };
            }

            chrome.privacy.services.autofillEnabled = makeSetting(false);
            chrome.privacy.services.autofillAddressEnabled = makeSetting(false);
            chrome.privacy.services.autofillCreditCardEnabled = makeSetting(false);
            chrome.privacy.services.passwordSavingEnabled = makeSetting(false);
            chrome.privacy.services.safeBrowsingEnabled = makeSetting(false);
            chrome.privacy.services.searchSuggestEnabled = makeSetting(false);
            chrome.privacy.services.spellingServiceEnabled = makeSetting(false);
            chrome.privacy.services.translationServiceEnabled = makeSetting(false);

            chrome.privacy.network.networkPredictionEnabled = makeSetting(false);
            chrome.privacy.network.webRTCIPHandlingPolicy = makeSetting('default');

            chrome.privacy.websites.thirdPartyCookiesAllowed = makeSetting(false);
            chrome.privacy.websites.hyperlinkAuditingEnabled = makeSetting(false);
            chrome.privacy.websites.referrersEnabled = makeSetting(true);
            chrome.privacy.websites.protectedContentEnabled = makeSetting(false);
        })();
        """
    }
}
