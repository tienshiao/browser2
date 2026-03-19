import XCTest
import WebKit
@testable import Detour

/// Integration tests verifying that the storage permission gate in ExtensionMessageBridge
/// correctly allows/denies chrome.storage.local.* calls based on manifest permissions.
@MainActor
final class StoragePermissionTests: XCTestCase {

    // Extension WITH storage permission
    private var allowedDir: URL!
    private var allowedExt: WebExtension!
    private var allowedWebView: WKWebView!
    private var allowedNavDelegate: TestStorageNavDelegate!

    // Extension WITHOUT storage permission
    private var deniedDir: URL!
    private var deniedExt: WebExtension!
    private var deniedWebView: WKWebView!
    private var deniedNavDelegate: TestStorageNavDelegate!

    @MainActor
    override func setUp() {
        super.setUp()

        // --- Extension with storage permission ---
        allowedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("detour-storage-allowed-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: allowedDir, withIntermediateDirectories: true)

        let allowedManifestJSON = """
        {
            "manifest_version": 3,
            "name": "Storage Allowed",
            "version": "1.0",
            "permissions": ["storage"]
        }
        """
        try! allowedManifestJSON.write(to: allowedDir.appendingPathComponent("manifest.json"),
                                       atomically: true, encoding: .utf8)

        let allowedManifest = try! ExtensionManifest.parse(at: allowedDir.appendingPathComponent("manifest.json"))
        let allowedID = "storage-allowed-\(UUID().uuidString)"
        allowedExt = WebExtension(id: allowedID, manifest: allowedManifest, basePath: allowedDir)
        ExtensionManager.shared.extensions.append(allowedExt)

        let allowedRecord = ExtensionRecord(
            id: allowedID, name: allowedManifest.name, version: allowedManifest.version,
            manifestJSON: try! allowedManifest.toJSONData(), basePath: allowedDir.path,
            isEnabled: true, installedAt: Date().timeIntervalSince1970)
        ExtensionDatabase.shared.saveExtension(allowedRecord)

        let allowedConfig = WKWebViewConfiguration()
        let allowedBundle = ChromeAPIBundle.generateBundle(for: allowedExt, isContentScript: false)
        let allowedScript = WKUserScript(source: allowedBundle, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        allowedConfig.userContentController.addUserScript(allowedScript)
        ExtensionMessageBridge.shared.register(on: allowedConfig.userContentController)
        allowedWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), configuration: allowedConfig)

        // --- Extension without storage permission ---
        deniedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("detour-storage-denied-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: deniedDir, withIntermediateDirectories: true)

        let deniedManifestJSON = """
        {
            "manifest_version": 3,
            "name": "Storage Denied",
            "version": "1.0",
            "permissions": []
        }
        """
        try! deniedManifestJSON.write(to: deniedDir.appendingPathComponent("manifest.json"),
                                      atomically: true, encoding: .utf8)

        let deniedManifest = try! ExtensionManifest.parse(at: deniedDir.appendingPathComponent("manifest.json"))
        let deniedID = "storage-denied-\(UUID().uuidString)"
        deniedExt = WebExtension(id: deniedID, manifest: deniedManifest, basePath: deniedDir)
        ExtensionManager.shared.extensions.append(deniedExt)

        let deniedRecord = ExtensionRecord(
            id: deniedID, name: deniedManifest.name, version: deniedManifest.version,
            manifestJSON: try! deniedManifest.toJSONData(), basePath: deniedDir.path,
            isEnabled: true, installedAt: Date().timeIntervalSince1970)
        ExtensionDatabase.shared.saveExtension(deniedRecord)

        let deniedConfig = WKWebViewConfiguration()
        let deniedBundle = ChromeAPIBundle.generateBundle(for: deniedExt, isContentScript: false)
        let deniedScript = WKUserScript(source: deniedBundle, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        deniedConfig.userContentController.addUserScript(deniedScript)
        ExtensionMessageBridge.shared.register(on: deniedConfig.userContentController)
        deniedWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), configuration: deniedConfig)

        // Load pages
        let html = "<html><body>test</body></html>"
        let allowedNavExp = expectation(description: "Allowed page loaded")
        allowedNavDelegate = TestStorageNavDelegate { allowedNavExp.fulfill() }
        allowedWebView.navigationDelegate = allowedNavDelegate
        allowedWebView.loadHTMLString(html, baseURL: URL(string: "https://storage-test.example.com")!)

        let deniedNavExp = expectation(description: "Denied page loaded")
        deniedNavDelegate = TestStorageNavDelegate { deniedNavExp.fulfill() }
        deniedWebView.navigationDelegate = deniedNavDelegate
        deniedWebView.loadHTMLString(html, baseURL: URL(string: "https://storage-test.example.com")!)

        wait(for: [allowedNavExp, deniedNavExp], timeout: 10.0)
    }

    @MainActor
    override func tearDown() {
        for ext in [allowedExt, deniedExt].compactMap({ $0 }) {
            ExtensionManager.shared.extensions.removeAll { $0.id == ext.id }
            ExtensionDatabase.shared.storageClear(extensionID: ext.id)
            ExtensionDatabase.shared.deleteExtension(id: ext.id)
        }
        allowedWebView = nil
        deniedWebView = nil
        allowedNavDelegate = nil
        deniedNavDelegate = nil
        allowedExt = nil
        deniedExt = nil
        if let d = allowedDir { try? FileManager.default.removeItem(at: d) }
        if let d = deniedDir { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
    }

    // MARK: - Allowed

    func testStorageSetGetAllowed() {
        callVoid(allowedWebView, "await chrome.storage.local.set({ key1: 'value1' })")
        let result = callAsync(allowedWebView, "var r = await chrome.storage.local.get('key1'); return r.key1;")
        XCTAssertEqual(result as? String, "value1")
    }

    func testStorageRemoveAllowed() {
        callVoid(allowedWebView, "await chrome.storage.local.set({ rmKey: 'x' })")
        callVoid(allowedWebView, "await chrome.storage.local.remove('rmKey')")
        let result = callAsync(allowedWebView, "var r = await chrome.storage.local.get('rmKey'); return r.rmKey === undefined;")
        XCTAssertEqual(result as? Bool, true)
    }

    func testStorageClearAllowed() {
        callVoid(allowedWebView, "await chrome.storage.local.set({ a: 1, b: 2 })")
        callVoid(allowedWebView, "await chrome.storage.local.clear()")
        let result = callAsync(allowedWebView, "var r = await chrome.storage.local.get(null); return Object.keys(r).length;")
        XCTAssertEqual(result as? Int, 0)
    }

    // MARK: - Denied

    func testStorageGetDenied() {
        let result = callAsync(deniedWebView, """
            try { await chrome.storage.local.get('x'); return 'resolved'; }
            catch (e) { return e.message; }
        """)
        let msg = result as? String ?? ""
        XCTAssertTrue(msg.contains("storage"), "Error should mention 'storage': \(msg)")
    }

    func testStorageSetDenied() {
        let result = callAsync(deniedWebView, """
            try { await chrome.storage.local.set({ x: 1 }); return 'resolved'; }
            catch (e) { return e.message; }
        """)
        let msg = result as? String ?? ""
        XCTAssertTrue(msg.contains("storage"), "Error should mention 'storage': \(msg)")
    }

    func testStorageRemoveDenied() {
        let result = callAsync(deniedWebView, """
            try { await chrome.storage.local.remove('x'); return 'resolved'; }
            catch (e) { return e.message; }
        """)
        let msg = result as? String ?? ""
        XCTAssertTrue(msg.contains("storage"), "Error should mention 'storage': \(msg)")
    }

    func testStorageClearDenied() {
        let result = callAsync(deniedWebView, """
            try { await chrome.storage.local.clear(); return 'resolved'; }
            catch (e) { return e.message; }
        """)
        let msg = result as? String ?? ""
        XCTAssertTrue(msg.contains("storage"), "Error should mention 'storage': \(msg)")
    }

    // MARK: - Helpers

    private func callAsync(_ webView: WKWebView, _ js: String) -> Any? {
        let exp = expectation(description: "Async JS")
        var result: Any?
        var evalError: Error?
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { res in
            switch res {
            case .success(let value): result = value
            case .failure(let error): evalError = error
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)
        if let evalError { XCTFail("JS error: \(evalError)") }
        return result
    }

    private func callVoid(_ webView: WKWebView, _ js: String) {
        _ = callAsync(webView, js)
    }
}

private class TestStorageNavDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
}
