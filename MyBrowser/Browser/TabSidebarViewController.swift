import AppKit

protocol TabSidebarDelegate: AnyObject {
    func tabSidebarDidRequestNewTab(_ sidebar: TabSidebarViewController)
    func tabSidebar(_ sidebar: TabSidebarViewController, didSelectTabAt index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestCloseTabAt index: Int)
    func tabSidebarDidRequestGoBack(_ sidebar: TabSidebarViewController)
    func tabSidebarDidRequestGoForward(_ sidebar: TabSidebarViewController)
    func tabSidebarDidRequestReload(_ sidebar: TabSidebarViewController)
    func tabSidebar(_ sidebar: TabSidebarViewController, didSubmitAddressInput input: String)
    func tabSidebarDidRequestToggleSidebar(_ sidebar: TabSidebarViewController)
}

class DraggableTableView: NSTableView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow >= 0 {
            super.mouseDown(with: event)
        } else {
            window?.performDrag(with: event)
        }
    }
}

class DraggableScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { true }
}

class DraggableClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { true }
}

class TabSidebarViewController: NSViewController {
    weak var delegate: TabSidebarDelegate?

    private(set) var tableView = DraggableTableView()
    private let scrollView = DraggableScrollView()
    private(set) var addressField = NSTextField()
    private(set) var backButton = NSButton()
    private(set) var forwardButton = NSButton()
    private(set) var reloadButton = NSButton()
    private(set) var sidebarToggleButton = NSButton()

    var tabs: [BrowserTab] = [] {
        didSet { tableView.reloadData() }
    }

    var selectedTabIndex: Int {
        get { tableView.selectedRow }
        set {
            guard newValue >= 0, newValue < tabs.count else { return }
            tableView.selectRowIndexes(IndexSet(integer: newValue), byExtendingSelection: false)
        }
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 400))

        // Navigation buttons (right-aligned, sitting in the title bar area)
        backButton = makeNavButton(symbolName: "chevron.left", accessibilityLabel: "Back", action: #selector(goBackClicked))
        forwardButton = makeNavButton(symbolName: "chevron.right", accessibilityLabel: "Forward", action: #selector(goForwardClicked))
        reloadButton = makeNavButton(symbolName: "arrow.clockwise", accessibilityLabel: "Reload", action: #selector(reloadClicked))

        // Sidebar toggle button (positioned next to traffic lights)
        sidebarToggleButton = makeNavButton(symbolName: "sidebar.left", accessibilityLabel: "Toggle Sidebar", action: #selector(toggleSidebarClicked))
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false

        let navStack = NSStackView(views: [backButton, forwardButton, reloadButton])
        navStack.orientation = .horizontal
        navStack.spacing = 2
        navStack.translatesAutoresizingMaskIntoConstraints = false

        // Address field
        addressField.placeholderString = "Enter URL or search"
        addressField.font = .systemFont(ofSize: NSFont.systemFontSize)
        addressField.target = self
        addressField.action = #selector(addressFieldSubmitted(_:))
        addressField.lineBreakMode = .byTruncatingTail
        addressField.usesSingleLineMode = true
        addressField.cell?.isScrollable = true
        addressField.bezelStyle = .roundedBezel
        addressField.translatesAutoresizingMaskIntoConstraints = false

        // Tab list
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TabColumn"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 36
        tableView.style = .sourceList

        scrollView.contentView = DraggableClipView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // New Tab button (styled like a tab cell)
        let newTabButton = HoverButton(frame: .zero)
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.target = self
        newTabButton.action = #selector(addTabClicked)
        newTabButton.translatesAutoresizingMaskIntoConstraints = false

        let plusIcon = NSImageView(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")!)
        plusIcon.translatesAutoresizingMaskIntoConstraints = false

        let newTabLabel = NSTextField(labelWithString: "New Tab")
        newTabLabel.lineBreakMode = .byTruncatingTail
        newTabLabel.translatesAutoresizingMaskIntoConstraints = false

        newTabButton.addSubview(plusIcon)
        newTabButton.addSubview(newTabLabel)

        NSLayoutConstraint.activate([
            plusIcon.leadingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: 20),
            plusIcon.centerYAnchor.constraint(equalTo: newTabButton.centerYAnchor),
            plusIcon.widthAnchor.constraint(equalToConstant: 16),
            plusIcon.heightAnchor.constraint(equalToConstant: 16),

            newTabLabel.leadingAnchor.constraint(equalTo: plusIcon.trailingAnchor, constant: 8),
            newTabLabel.centerYAnchor.constraint(equalTo: newTabButton.centerYAnchor),
            newTabLabel.trailingAnchor.constraint(lessThanOrEqualTo: newTabButton.trailingAnchor, constant: -4),
        ])

        container.addSubview(sidebarToggleButton)
        container.addSubview(navStack)
        container.addSubview(addressField)
        container.addSubview(newTabButton)
        container.addSubview(scrollView)

        // The title bar is ~38px tall. Nav buttons sit in that area, right-aligned.
        // Traffic lights occupy roughly the left 70px, so right-aligning the nav buttons avoids overlap.
        NSLayoutConstraint.activate([
            // Sidebar toggle button: in title bar area, right of traffic lights
            sidebarToggleButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            sidebarToggleButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 74),

            // Nav buttons: pinned to top of view (title bar area), right-aligned
            navStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            navStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            navStack.heightAnchor.constraint(equalToConstant: 24),

            // Address field: below title bar area
            addressField.topAnchor.constraint(equalTo: container.topAnchor, constant: 38),
            addressField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            addressField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            // New Tab button: below address field
            newTabButton.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 8),
            newTabButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            newTabButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            newTabButton.heightAnchor.constraint(equalToConstant: 36),

            // Tab list: below new tab button, fills remaining space
            scrollView.topAnchor.constraint(equalTo: newTabButton.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    private func makeNavButton(symbolName: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    // MARK: - Actions

    @objc private func goBackClicked() {
        delegate?.tabSidebarDidRequestGoBack(self)
    }

    @objc private func goForwardClicked() {
        delegate?.tabSidebarDidRequestGoForward(self)
    }

    @objc private func reloadClicked() {
        delegate?.tabSidebarDidRequestReload(self)
    }

    @objc private func addressFieldSubmitted(_ sender: NSTextField) {
        delegate?.tabSidebar(self, didSubmitAddressInput: sender.stringValue)
    }

    @objc private func addTabClicked() {
        delegate?.tabSidebarDidRequestNewTab(self)
    }

    @objc private func toggleSidebarClicked() {
        delegate?.tabSidebarDidRequestToggleSidebar(self)
    }

    func reloadTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
    }
}

// MARK: - NSTableViewDataSource

extension TabSidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tabs.count
    }
}

// MARK: - NSTableViewDelegate

extension TabSidebarViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("TabCell")
        let cell: TabCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? TabCellView {
            cell = existing
        } else {
            cell = TabCellView()
            cell.identifier = cellID
        }

        let tab = tabs[row]
        cell.titleLabel.stringValue = tab.title
        cell.toolTip = tab.title
        cell.updateFavicon(tab.favicon)
        cell.onClose = { [weak self] in
            guard let self else { return }
            self.delegate?.tabSidebar(self, didRequestCloseTabAt: row)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        TabRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.tabSidebar(self, didSelectTabAt: row)
    }
}

