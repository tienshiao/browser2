import AppKit
import WebKit
import Combine

class BrowserWindowController: NSWindowController {
    private let splitViewController = NSSplitViewController()
    private let tabSidebar = TabSidebarViewController()
    private let contentContainerView = NSView()

    private var tabs: [BrowserTab] = []
    private var activeTab: BrowserTab?
    private var subscriptions: [UUID: Set<AnyCancellable>] = [:]

    private let addressField = NSTextField()

    private static let backIdentifier = NSToolbarItem.Identifier("back")
    private static let forwardIdentifier = NSToolbarItem.Identifier("forward")
    private static let reloadIdentifier = NSToolbarItem.Identifier("reload")
    private static let addressFieldIdentifier = NSToolbarItem.Identifier("addressField")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("BrowserWindow")
        window.minSize = NSSize(width: 600, height: 400)
        window.titleVisibility = .hidden

        self.init(window: window)

        setupSplitView()
        setupToolbar()
        addNewTab(url: URL(string: "https://www.apple.com")!)
    }

    // MARK: - Setup

    private func setupSplitView() {
        tabSidebar.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: tabSidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        splitViewController.addSplitViewItem(sidebarItem)

        let contentVC = NSViewController()
        contentVC.view = contentContainerView
        contentContainerView.wantsLayer = true
        let contentItem = NSSplitViewItem(viewController: contentVC)
        splitViewController.addSplitViewItem(contentItem)

        window?.contentViewController = splitViewController
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "BrowserToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    // MARK: - Tab Management

    func addNewTab(url: URL? = nil) {
        let tab = BrowserTab()
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tabs.append(tab)

        var cancellables = Set<AnyCancellable>()

        tab.$title
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let index = self.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                self.tabSidebar.reloadTab(at: index)
                if self.activeTab?.id == tab.id {
                    self.window?.title = tab.title
                }
            }
            .store(in: &cancellables)

        tab.$url
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                guard let self, self.activeTab?.id == tab.id else { return }
                self.addressField.stringValue = url?.absoluteString ?? ""
            }
            .store(in: &cancellables)

        subscriptions[tab.id] = cancellables
        tabSidebar.tabs = tabs
        selectTab(at: tabs.count - 1)

        if let url {
            tab.load(url)
        }
    }

    private func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }

        activeTab?.webView.removeFromSuperview()

        let tab = tabs[index]
        activeTab = tab

        let webView = tab.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
        ])

        addressField.stringValue = tab.url?.absoluteString ?? ""
        window?.title = tab.title
        tabSidebar.selectedTabIndex = index
    }

    private func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }

        let tab = tabs[index]
        subscriptions.removeValue(forKey: tab.id)
        tab.webView.removeFromSuperview()
        tabs.remove(at: index)
        tabSidebar.tabs = tabs

        if tabs.isEmpty {
            addNewTab()
        } else if activeTab?.id == tab.id {
            let newIndex = min(index, tabs.count - 1)
            selectTab(at: newIndex)
        }
    }

    // MARK: - Navigation

    private func navigateToAddress() {
        guard let tab = activeTab else { return }
        let input = addressField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        if let url = urlFromInput(input) {
            tab.load(url)
        }
    }

    private func urlFromInput(_ input: String) -> URL? {
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            return URL(string: input)
        }
        if input.contains(".") && !input.contains(" ") {
            return URL(string: "https://\(input)")
        }
        let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }

    // MARK: - Actions

    @objc func newTab(_ sender: Any?) {
        addNewTab()
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        guard let active = activeTab, let index = tabs.firstIndex(where: { $0.id == active.id }) else { return }
        closeTab(at: index)
    }

    @objc private func goBack(_ sender: Any?) {
        activeTab?.webView.goBack()
    }

    @objc private func goForward(_ sender: Any?) {
        activeTab?.webView.goForward()
    }

    @objc private func reload(_ sender: Any?) {
        activeTab?.webView.reload()
    }

    @objc private func addressFieldAction(_ sender: NSTextField) {
        navigateToAddress()
    }
}

// MARK: - NSToolbarDelegate

extension BrowserWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.backIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
            item.label = "Back"
            item.target = self
            item.action = #selector(goBack(_:))
            return item

        case Self.forwardIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
            item.label = "Forward"
            item.target = self
            item.action = #selector(goForward(_:))
            return item

        case Self.reloadIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            item.label = "Reload"
            item.target = self
            item.action = #selector(reload(_:))
            return item

        case Self.addressFieldIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            addressField.placeholderString = "Enter URL or search"
            addressField.font = .systemFont(ofSize: NSFont.systemFontSize)
            addressField.target = self
            addressField.action = #selector(addressFieldAction(_:))
            addressField.lineBreakMode = .byTruncatingTail
            addressField.usesSingleLineMode = true
            addressField.cell?.isScrollable = true
            item.view = addressField
            item.minSize = NSSize(width: 200, height: 22)
            item.maxSize = NSSize(width: 10000, height: 22)
            return item

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backIdentifier, Self.forwardIdentifier, Self.reloadIdentifier, Self.addressFieldIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backIdentifier, Self.forwardIdentifier, Self.reloadIdentifier, Self.addressFieldIdentifier]
    }
}

// MARK: - TabSidebarDelegate

extension BrowserWindowController: TabSidebarDelegate {
    func tabSidebarDidRequestNewTab(_ sidebar: TabSidebarViewController) {
        addNewTab()
    }

    func tabSidebar(_ sidebar: TabSidebarViewController, didSelectTabAt index: Int) {
        selectTab(at: index)
    }

    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestCloseTabAt index: Int) {
        closeTab(at: index)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        .allow
    }
}

// MARK: - WKUIDelegate

extension BrowserWindowController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            addNewTab(url: url)
        }
        return nil
    }
}
