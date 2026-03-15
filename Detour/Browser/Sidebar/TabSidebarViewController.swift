import AppKit

protocol TabSidebarDelegate: AnyObject {
    func tabSidebarDidRequestNewTab(_ sidebar: TabSidebarViewController)
    func tabSidebar(_ sidebar: TabSidebarViewController, didSelectTabAt index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didSelectPinnedTabAt index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestCloseTabAt index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestClosePinnedTabAt index: Int)
    func tabSidebarDidRequestGoBack(_ sidebar: TabSidebarViewController)
    func tabSidebarDidRequestGoForward(_ sidebar: TabSidebarViewController)
    func tabSidebarDidRequestReload(_ sidebar: TabSidebarViewController)
    func tabSidebarDidRequestOpenCommandPalette(_ sidebar: TabSidebarViewController, anchorFrame: NSRect)
    func tabSidebarDidRequestToggleSidebar(_ sidebar: TabSidebarViewController)
    func tabSidebar(_ sidebar: TabSidebarViewController, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didMovePinnedTabFrom sourceIndex: Int, to destinationIndex: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didDragTabToPinAt index: Int, destinationIndex: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didDragPinnedTabToUnpinAt index: Int, destinationIndex: Int)
    func tabSidebarDidRequestSwitchToSpace(_ sidebar: TabSidebarViewController, spaceID: UUID)
    func tabSidebarDidRequestAddSpace(_ sidebar: TabSidebarViewController, sourceButton: NSButton)
    func tabSidebarDidRequestEditSpace(_ sidebar: TabSidebarViewController, spaceID: UUID, sourceButton: NSButton)
    func tabSidebarDidRequestDeleteSpace(_ sidebar: TabSidebarViewController, spaceID: UUID)
    func tabSidebarDidRequestShowDownloads(_ sidebar: TabSidebarViewController, sourceButton: NSButton)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestDuplicateTabAt index: Int, isPinned: Bool)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestMoveTabAt index: Int, isPinned: Bool, toSpaceID: UUID)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestArchiveTabAt index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestArchiveTabsBelowIndex index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestPinTabAt index: Int)
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestUnpinTabAt index: Int)
    func tabSidebarSpacesForContextMenu(_ sidebar: TabSidebarViewController) -> [(id: UUID, name: String, emoji: String, isCurrent: Bool)]
}

extension TabSidebarDelegate {
    func tabSidebarDidRequestShowDownloads(_ sidebar: TabSidebarViewController, sourceButton: NSButton) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didSelectPinnedTabAt index: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestClosePinnedTabAt index: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didMovePinnedTabFrom sourceIndex: Int, to destinationIndex: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didDragTabToPinAt index: Int, destinationIndex: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didDragPinnedTabToUnpinAt index: Int, destinationIndex: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestDuplicateTabAt index: Int, isPinned: Bool) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestMoveTabAt index: Int, isPinned: Bool, toSpaceID: UUID) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestArchiveTabAt index: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestArchiveTabsBelowIndex index: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestPinTabAt index: Int) {}
    func tabSidebar(_ sidebar: TabSidebarViewController, didRequestUnpinTabAt index: Int) {}
    func tabSidebarSpacesForContextMenu(_ sidebar: TabSidebarViewController) -> [(id: UUID, name: String, emoji: String, isCurrent: Bool)] { [] }
}

private let tabReorderPasteboardType = NSPasteboard.PasteboardType("com.mybrowser.tab-reorder")

class TabSidebarViewController: NSViewController {
    weak var delegate: TabSidebarDelegate?
    var isIncognito = false

    // Active page views — updated by updateActivePage()
    private(set) var tableView = DraggableTableView()
    private var scrollView = DraggableScrollView()

    private(set) var fauxAddressBar = FauxAddressBar()
    private(set) var backButton = HoverButton()
    private(set) var forwardButton = HoverButton()
    private(set) var reloadButton = HoverButton()
    private(set) var sidebarToggleButton = HoverButton()

    private var contextMenuTabIndex: Int = -1
    private var contextMenuTabIsPinned: Bool = false

    private(set) var downloadButton = HoverButton()
    private lazy var downloadBadge: NSView = {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemBlue.cgColor
        badge.layer?.cornerRadius = 3
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        return badge
    }()

    private var suppressReload = false
    private var bottomBar = DraggableBarView()
    private var spaceButtonsContainer = NSStackView()
    private var addSpaceButton = HoverButton()
    private var isAnimatingSwipe = false

    // Page strip: all spaces laid out side-by-side, clipped by pageClipView
    private let pageClipView = NSView()
    private let pageStripView = NSView()
    private var pageScrollViews: [DraggableScrollView] = []
    private var pageTableViews: [DraggableTableView] = []
    private var pageSpaceIDs: [UUID] = []
    private var activePageIndex = 0
    private var topFadeShadow: NSView!
    private var bottomFadeShadow: NSView!

    var activeSpaceID: UUID? {
        didSet { updateActivePage() }
    }

    var pinnedTabs: [BrowserTab] = [] {
        didSet {
            if !suppressReload { tableView.reloadData() }
        }
    }

    var tabs: [BrowserTab] = [] {
        didSet {
            if !suppressReload { tableView.reloadData() }
        }
    }

    /// Set both arrays atomically with a single reload.
    func setTabs(pinned: [BrowserTab], normal: [BrowserTab]) {
        let wasSuppressed = suppressReload
        suppressReload = true
        pinnedTabs = pinned
        suppressReload = wasSuppressed
        tabs = normal  // triggers reload only if not externally suppressed
    }

    // MARK: - Animated Insert/Remove

    func insertTab(at index: Int, tabs newTabs: [BrowserTab]) {
        // If suppressReload is already set, a drag handler is managing animations
        if suppressReload { tabs = newTabs; return }
        suppressReload = true
        tabs = newTabs
        suppressReload = false
        let row = rowForNormalTab(at: index)
        tableView.insertRows(at: IndexSet(integer: row), withAnimation: .slideDown)
        recheckHoverForVisibleCells()
    }

    func removeTab(at index: Int, tabs newTabs: [BrowserTab]) {
        if suppressReload { tabs = newTabs; return }
        let row = rowForNormalTab(at: index)
        suppressReload = true
        tabs = newTabs
        suppressReload = false
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)
        recheckHoverForVisibleCells()
    }

    func insertPinnedTab(at index: Int, pinnedTabs newPinned: [BrowserTab]) {
        if suppressReload { pinnedTabs = newPinned; return }
        suppressReload = true
        pinnedTabs = newPinned
        suppressReload = false
        tableView.insertRows(at: IndexSet(integer: rowForPinnedTab(at: index)), withAnimation: .slideDown)
        recheckHoverForVisibleCells()
    }

    func removePinnedTab(at index: Int, pinnedTabs newPinned: [BrowserTab]) {
        if suppressReload { pinnedTabs = newPinned; return }
        let row = rowForPinnedTab(at: index)
        suppressReload = true
        pinnedTabs = newPinned
        suppressReload = false
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)
        recheckHoverForVisibleCells()
    }

    // MARK: - Animated Pin/Unpin

    func pinTab(fromNormalIndex srcIdx: Int, toPinnedIndex dstIdx: Int,
                tabs newTabs: [BrowserTab], pinnedTabs newPinned: [BrowserTab]) {
        if suppressReload { tabs = newTabs; pinnedTabs = newPinned; return }
        let oldRow = rowForNormalTab(at: srcIdx)
        suppressReload = true
        tabs = newTabs
        pinnedTabs = newPinned
        suppressReload = false
        tableView.beginUpdates()
        tableView.moveRow(at: oldRow, to: rowForPinnedTab(at: dstIdx))
        tableView.endUpdates()
    }

    func unpinTab(fromPinnedIndex srcIdx: Int, toNormalIndex dstIdx: Int,
                  tabs newTabs: [BrowserTab], pinnedTabs newPinned: [BrowserTab]) {
        if suppressReload { tabs = newTabs; pinnedTabs = newPinned; return }
        let oldRow = rowForPinnedTab(at: srcIdx)
        suppressReload = true
        tabs = newTabs
        pinnedTabs = newPinned
        suppressReload = false
        tableView.beginUpdates()
        tableView.moveRow(at: oldRow, to: rowForNormalTab(at: dstIdx))
        tableView.endUpdates()
    }

    // MARK: - Row Layout

    func sidebarRow(for row: Int, pinnedCount: Int? = nil) -> SidebarRow {
        let pc = pinnedCount ?? pinnedTabs.count
        return Detour.sidebarRow(for: row, pinnedCount: pc)
    }

    private func totalRowCount(forTableView tv: NSTableView) -> Int {
        let (p, t) = tabsAndPinnedForTableView(tv)
        return totalSidebarRowCount(pinnedCount: p.count, tabCount: t.count)
    }

    func rowForNormalTab(at tabIndex: Int) -> Int {
        return Detour.rowForNormalTab(at: tabIndex, pinnedCount: pinnedTabs.count)
    }

    func rowForPinnedTab(at index: Int) -> Int {
        return Detour.rowForPinnedTab(at: index)
    }

    var tintColor: NSColor? {
        didSet {
            view.wantsLayer = true
            if let color = tintColor {
                view.layer?.backgroundColor = color.withAlphaComponent(0.1).cgColor
            } else {
                view.layer?.backgroundColor = nil
            }
            tableView.enumerateAvailableRowViews { rowView, _ in
                (rowView as? TabRowView)?.selectionColor = tintColor
            }
        }
    }

    var selectedTabIndex: Int {
        get {
            let row = tableView.selectedRow
            switch sidebarRow(for: row) {
            case .normalTab(let index): return index
            default: return -1
            }
        }
        set {
            guard newValue >= 0, newValue < tabs.count else { return }
            tableView.selectRowIndexes(IndexSet(integer: rowForNormalTab(at: newValue)), byExtendingSelection: false)
        }
    }

    var selectedPinnedTabIndex: Int {
        get {
            let row = tableView.selectedRow
            switch sidebarRow(for: row) {
            case .pinnedTab(let index): return index
            default: return -1
            }
        }
        set {
            guard newValue >= 0, newValue < pinnedTabs.count else { return }
            tableView.selectRowIndexes(IndexSet(integer: rowForPinnedTab(at: newValue)), byExtendingSelection: false)
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

        // Faux address bar
        fauxAddressBar.translatesAutoresizingMaskIntoConstraints = false
        fauxAddressBar.onClick = { [weak self] in
            guard let self else { return }
            let frameInWindow = self.fauxAddressBar.convert(self.fauxAddressBar.bounds, to: nil)
            self.delegate?.tabSidebarDidRequestOpenCommandPalette(self, anchorFrame: frameInWindow)
        }

        // Bottom bar for spaces
        bottomBar.wantsLayer = true
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        // Space buttons container (centered)
        spaceButtonsContainer.orientation = .horizontal
        spaceButtonsContainer.spacing = 4
        spaceButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(spaceButtonsContainer)

        // Add space button
        let boldConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        addSpaceButton = HoverButton()
        addSpaceButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Space")?.withSymbolConfiguration(boldConfig)
        addSpaceButton.bezelStyle = .inline
        addSpaceButton.isBordered = false
        addSpaceButton.imagePosition = .imageOnly
        addSpaceButton.circular = true
        addSpaceButton.target = self
        addSpaceButton.action = #selector(addSpaceClicked)
        addSpaceButton.translatesAutoresizingMaskIntoConstraints = false
        addSpaceButton.toolTip = "Add Space"
        bottomBar.addSubview(addSpaceButton)

        // Download button
        downloadButton = HoverButton()
        downloadButton.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloads")?.withSymbolConfiguration(boldConfig)
        downloadButton.bezelStyle = .inline
        downloadButton.isBordered = false
        downloadButton.imagePosition = .imageOnly
        downloadButton.circular = true
        downloadButton.target = self
        downloadButton.action = #selector(downloadButtonClicked)
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.wantsLayer = true
        downloadButton.toolTip = "Downloads"
        bottomBar.addSubview(downloadButton)
        bottomBar.addSubview(downloadBadge)

        NSLayoutConstraint.activate([
            spaceButtonsContainer.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            spaceButtonsContainer.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: 0.5),

            downloadButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 8),
            downloadButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: 0.5),
            downloadButton.widthAnchor.constraint(equalToConstant: 24),
            downloadButton.heightAnchor.constraint(equalToConstant: 24),

            addSpaceButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -8),
            addSpaceButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: 0.5),
            addSpaceButton.widthAnchor.constraint(equalToConstant: 24),
            addSpaceButton.heightAnchor.constraint(equalToConstant: 24),

            downloadBadge.widthAnchor.constraint(equalToConstant: 6),
            downloadBadge.heightAnchor.constraint(equalToConstant: 6),
            downloadBadge.leadingAnchor.constraint(equalTo: downloadButton.trailingAnchor, constant: -9),
            downloadBadge.topAnchor.constraint(equalTo: downloadButton.topAnchor, constant: 1),
        ])

        // Page clip view (clips the horizontal page strip)
        pageClipView.wantsLayer = true
        pageClipView.layer?.masksToBounds = true
        pageClipView.translatesAutoresizingMaskIntoConstraints = false
        pageClipView.addSubview(pageStripView)

        container.addSubview(sidebarToggleButton)
        container.addSubview(navStack)
        container.addSubview(fauxAddressBar)
        container.addSubview(pageClipView)
        container.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            // Sidebar toggle button: in title bar area, right of traffic lights
            sidebarToggleButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            sidebarToggleButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 74),

            // Nav buttons: pinned to top of view (title bar area), right-aligned
            navStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            navStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            navStack.heightAnchor.constraint(equalToConstant: 24),

            // Address field: below title bar area
            fauxAddressBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 38),
            fauxAddressBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            fauxAddressBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            // Page clip: below address field, above bottom bar
            fauxAddressBar.heightAnchor.constraint(equalToConstant: 34),

            pageClipView.topAnchor.constraint(equalTo: fauxAddressBar.bottomAnchor, constant: 8),
            pageClipView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pageClipView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pageClipView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            // Bottom bar: pinned to bottom
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Scroll edge fade shadows
        topFadeShadow = makeFadeShadow(flipped: true)
        bottomFadeShadow = makeFadeShadow(flipped: false)
        pageClipView.addSubview(topFadeShadow, positioned: .above, relativeTo: pageStripView)
        pageClipView.addSubview(bottomFadeShadow, positioned: .above, relativeTo: pageStripView)

        NSLayoutConstraint.activate([
            topFadeShadow.topAnchor.constraint(equalTo: pageClipView.topAnchor),
            topFadeShadow.leadingAnchor.constraint(equalTo: pageClipView.leadingAnchor),
            topFadeShadow.trailingAnchor.constraint(equalTo: pageClipView.trailingAnchor),
            topFadeShadow.heightAnchor.constraint(equalToConstant: 12),

            bottomFadeShadow.bottomAnchor.constraint(equalTo: pageClipView.bottomAnchor),
            bottomFadeShadow.leadingAnchor.constraint(equalTo: pageClipView.leadingAnchor),
            bottomFadeShadow.trailingAnchor.constraint(equalTo: pageClipView.trailingAnchor),
            bottomFadeShadow.heightAnchor.constraint(equalToConstant: 12),
        ])

        container.allowedTouchTypes = .indirect
        self.view = container
    }

    private func makeFadeShadow(flipped: Bool) -> NSView {
        let view = FadeShadowView(flipped: flipped)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alphaValue = 0
        return view
    }

    private func updateFadeShadows() {
        guard let clipView = scrollView.contentView as? NSClipView else { return }
        guard let documentView = scrollView.documentView else { return }

        let contentHeight = documentView.frame.height
        let visibleHeight = clipView.bounds.height
        let scrollY = clipView.bounds.origin.y

        let showTop = scrollY > 0
        let showBottom = contentHeight - visibleHeight - scrollY > 0.5

        let targetTopAlpha: CGFloat = showTop ? 1 : 0
        let targetBottomAlpha: CGFloat = showBottom ? 1 : 0

        guard topFadeShadow.alphaValue != targetTopAlpha || bottomFadeShadow.alphaValue != targetBottomAlpha else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            topFadeShadow.animator().alphaValue = targetTopAlpha
            bottomFadeShadow.animator().alphaValue = targetBottomAlpha
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        relayoutPages()
        updateFadeShadows()
    }

    // MARK: - Page Management

    func rebuildPages() {
        let spaces = relevantSpaces
        let newIDs = spaces.map { $0.id }
        guard newIDs != pageSpaceIDs else {
            // Space list unchanged, just update active page
            updateActivePage()
            return
        }
        pageSpaceIDs = newIDs

        // Tear down old pages
        for sv in pageScrollViews {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: sv.contentView)
            sv.removeFromSuperview()
        }
        pageScrollViews.removeAll()
        pageTableViews.removeAll()

        // Build one scroll view + table view per space
        for _ in spaces {
            let tv = DraggableTableView()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TabColumn"))
            tv.addTableColumn(column)
            tv.headerView = nil
            tv.rowHeight = 36
            tv.style = .sourceList
            tv.dataSource = self
            tv.delegate = self
            tv.registerForDraggedTypes([tabReorderPasteboardType])
            tv.draggingDestinationFeedbackStyle = .sourceList

            let menu = NSMenu()
            menu.delegate = self
            tv.menu = menu

            let sv = DraggableScrollView()
            sv.contentView = DraggableClipView()
            sv.documentView = tv
            sv.hasVerticalScroller = true
            sv.horizontalScrollElasticity = .none
            sv.drawsBackground = false
            sv.onScrollWheel = { [weak self] in self?.handleSpaceSwipe($0) ?? false }

            pageStripView.addSubview(sv)
            pageScrollViews.append(sv)
            pageTableViews.append(tv)
        }

        relayoutPages()
        updateActivePage()

        // Observe scroll (clip view bounds changes) to fix hover state on scroll
        for sv in pageScrollViews {
            sv.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: sv.contentView
            )
        }

        // Reload all non-active pages from TabStore
        for (i, tv) in pageTableViews.enumerated() where i != activePageIndex {
            tv.reloadData()
        }
    }

    private func relayoutPages() {
        let pageW = pageClipView.bounds.width
        let pageH = pageClipView.bounds.height
        guard pageW > 0 else { return }

        for (i, sv) in pageScrollViews.enumerated() {
            sv.frame = NSRect(x: CGFloat(i) * pageW, y: 0, width: pageW, height: pageH)
        }
        pageStripView.frame = NSRect(
            x: -CGFloat(activePageIndex) * pageW,
            y: 0,
            width: CGFloat(max(1, pageScrollViews.count)) * pageW,
            height: pageH)
    }

    private func updateActivePage() {
        let spaces = relevantSpaces
        let newIndex: Int
        if let id = activeSpaceID, let idx = spaces.firstIndex(where: { $0.id == id }) {
            newIndex = idx
        } else {
            newIndex = 0
        }
        guard newIndex < pageScrollViews.count else { return }

        activePageIndex = newIndex
        scrollView = pageScrollViews[newIndex]
        tableView = pageTableViews[newIndex]

        // Snap strip to active page (no animation)
        let pageW = pageClipView.bounds.width
        if pageW > 0 {
            pageStripView.frame.origin.x = -CGFloat(newIndex) * pageW
        }

        updateFadeShadows()
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView,
              let scrollView = clipView.enclosingScrollView as? DraggableScrollView,
              let pageIndex = pageScrollViews.firstIndex(of: scrollView) else { return }
        recheckHoverForVisibleCells(in: pageTableViews[pageIndex])

        if pageIndex == activePageIndex {
            updateFadeShadows()
        }
    }

    private func recheckHoverForVisibleCells(in tv: NSTableView? = nil) {
        let targetTV = tv ?? tableView
        DispatchQueue.main.async { [weak self, weak targetTV] in
            guard self != nil, let tv = targetTV else { return }
            let visibleRows = tv.rows(in: tv.visibleRect)
            for row in visibleRows.lowerBound..<visibleRows.upperBound {
                guard let cellView = tv.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
                if let tabCell = cellView as? TabCellView {
                    tabCell.recheckHover()
                } else if let newTabCell = cellView as? NewTabCellView {
                    newTabCell.recheckHover()
                }
            }
        }
    }

    func updateSpaceButtons(spaces: [Space], activeSpaceID: UUID?) {
        // Remove old buttons
        for view in spaceButtonsContainer.arrangedSubviews {
            spaceButtonsContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Hide "Add Space" button in incognito mode
        addSpaceButton.isHidden = isIncognito

        for space in spaces {
            let button = NSButton()
            button.title = space.emoji
            button.font = .systemFont(ofSize: 14)
            button.bezelStyle = .inline
            button.isBordered = false
            button.target = self
            button.action = #selector(spaceButtonClicked(_:))
            button.tag = spaces.firstIndex(where: { $0.id == space.id }) ?? 0
            button.toolTip = isIncognito ? "Private Browsing" : space.name
            button.wantsLayer = true

            if space.id == activeSpaceID {
                button.layer?.backgroundColor = space.color.withAlphaComponent(0.15).cgColor
                button.layer?.cornerRadius = UIConstants.defaultCornerRadius
            }

            // No context menu in incognito mode
            if !isIncognito {
                let menu = NSMenu()
                let editItem = NSMenuItem(title: "Edit Space…", action: #selector(editSpaceClicked(_:)), keyEquivalent: "")
                editItem.target = self
                editItem.tag = button.tag
                let deleteItem = NSMenuItem(title: "Delete Space", action: #selector(deleteSpaceClicked(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.tag = button.tag
                menu.addItem(editItem)
                menu.addItem(deleteItem)
                button.menu = menu
            }

            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 24),
            ])

            spaceButtonsContainer.addArrangedSubview(button)
        }

        rebuildPages()
    }

    private func makeNavButton(symbolName: String, accessibilityLabel: String, action: Selector) -> HoverButton {
        let button = HoverButton()
        let boldConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?.withSymbolConfiguration(boldConfig)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.circular = true
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

    @objc private func addTabClicked() {
        delegate?.tabSidebarDidRequestNewTab(self)
    }

    @objc private func toggleSidebarClicked() {
        delegate?.tabSidebarDidRequestToggleSidebar(self)
    }

    @objc private func spaceButtonClicked(_ sender: NSButton) {
        let spaces = relevantSpaces
        guard sender.tag >= 0, sender.tag < spaces.count else { return }
        animateToSpace(id: spaces[sender.tag].id)
    }

    private func animateToSpace(id: UUID) {
        let spaces = relevantSpaces
        guard let targetIndex = spaces.firstIndex(where: { $0.id == id }),
              targetIndex != activePageIndex,
              !isAnimatingSwipe else {
            delegate?.tabSidebarDidRequestSwitchToSpace(self, spaceID: id)
            return
        }

        let pageW = pageClipView.bounds.width
        guard pageW > 0 else {
            delegate?.tabSidebarDidRequestSwitchToSpace(self, spaceID: id)
            return
        }

        isAnimatingSwipe = true
        let targetX = -CGFloat(targetIndex) * pageW
        let distance = abs(pageStripView.frame.origin.x - targetX)
        let duration = min(0.15, max(0.08, Double(distance / pageW) * 0.12))
        let targetColor = spaces[targetIndex].color

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            var frame = pageStripView.frame
            frame.origin.x = targetX
            pageStripView.animator().frame = frame
            view.animator().layer?.backgroundColor = targetColor.withAlphaComponent(0.1).cgColor
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.isAnimatingSwipe = false
            self.delegate?.tabSidebarDidRequestSwitchToSpace(self, spaceID: id)
        })
    }

    @objc private func downloadButtonClicked() {
        delegate?.tabSidebarDidRequestShowDownloads(self, sourceButton: downloadButton)
    }

    func updateDownloadBadge(hasActive: Bool) {
        downloadBadge.isHidden = !hasActive
    }

    @objc private func addSpaceClicked() {
        delegate?.tabSidebarDidRequestAddSpace(self, sourceButton: addSpaceButton)
    }

    @objc private func editSpaceClicked(_ sender: NSMenuItem) {
        let spaces = relevantSpaces
        guard sender.tag >= 0, sender.tag < spaces.count else { return }
        let spaceID = spaces[sender.tag].id
        let button = spaceButtonsContainer.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.tag == sender.tag } ?? addSpaceButton
        delegate?.tabSidebarDidRequestEditSpace(self, spaceID: spaceID, sourceButton: button)
    }

    @objc private func deleteSpaceClicked(_ sender: NSMenuItem) {
        let spaces = relevantSpaces
        guard sender.tag >= 0, sender.tag < spaces.count else { return }
        let spaceID = spaces[sender.tag].id
        delegate?.tabSidebarDidRequestDeleteSpace(self, spaceID: spaceID)
    }

    // MARK: - Swipe Paging

    private var swipeAccumulatedX: CGFloat = 0
    private var isTrackingHorizontalSwipe = false
    private var swipeStartTintColor: NSColor?
    private var swipeEventMonitor: Any?
    private var lastProcessedSwipeEvent: NSEvent?

    /// Returns `true` when the event is consumed by horizontal swipe handling.
    @discardableResult
    private func handleSpaceSwipe(_ event: NSEvent) -> Bool {
        if isIncognito { return false }

        // Already tracking — delegate to the shared processor (deduplicates with monitor)
        if isTrackingHorizontalSwipe {
            return processSwipeEvent(event)
        }

        // Momentum events with no active tracking — ignore
        if event.phase == [] { return false }

        if event.phase.contains(.began) {
            // If the previous gesture left the strip displaced, snap it back
            if isAnimatingSwipe {
                isAnimatingSwipe = false
                let pageW = pageClipView.bounds.width
                if pageW > 0 {
                    pageStripView.frame.origin.x = -CGFloat(activePageIndex) * pageW
                }
                if let startColor = swipeStartTintColor {
                    view.layer?.backgroundColor = startColor.withAlphaComponent(0.1).cgColor
                }
            }
            swipeAccumulatedX = 0
        }

        guard !isAnimatingSwipe else { return true }

        // Detect horizontal swipe start
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              event.scrollingDeltaX != 0 else { return false }
        isTrackingHorizontalSwipe = true
        swipeStartTintColor = tintColor
        installSwipeMonitor()
        return processSwipeEvent(event)
    }

    /// Processes a single scroll event for the horizontal swipe. Returns true if consumed.
    /// Called from both the scroll view handler and the app-level monitor;
    /// deduplicates via identity check so each event is processed exactly once.
    @discardableResult
    private func processSwipeEvent(_ event: NSEvent) -> Bool {
        if event === lastProcessedSwipeEvent { return true }
        lastProcessedSwipeEvent = event

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.phase == [] {
            isTrackingHorizontalSwipe = false
            removeSwipeMonitor()
            handleSwipeEnd()
            return true
        }

        swipeAccumulatedX += event.scrollingDeltaX
        updateStripPosition()
        return true
    }

    /// App-level monitor that captures ALL scroll events during a horizontal swipe,
    /// so the swipe continues even when the view moves out from under the cursor.
    private func installSwipeMonitor() {
        removeSwipeMonitor()
        swipeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isTrackingHorizontalSwipe else { return event }
            self.processSwipeEvent(event)
            return event
        }
    }

    private func removeSwipeMonitor() {
        if let monitor = swipeEventMonitor {
            NSEvent.removeMonitor(monitor)
            swipeEventMonitor = nil
        }
    }

    private func updateStripPosition() {
        let pageW = pageClipView.bounds.width
        guard pageW > 0 else { return }

        let baseX = -CGFloat(activePageIndex) * pageW
        let maxX: CGFloat = 0
        let minX = -CGFloat(max(0, pageScrollViews.count - 1)) * pageW

        var targetX = baseX + swipeAccumulatedX
        // Rubber-band at edges — logarithmic curve for gradually increasing resistance
        if targetX > maxX {
            let overflow = targetX - maxX
            targetX = maxX + pageW * (1 - 1 / (overflow / pageW + 1))
        } else if targetX < minX {
            let overflow = minX - targetX
            targetX = minX - pageW * (1 - 1 / (overflow / pageW + 1))
        }

        pageStripView.frame.origin.x = targetX

        // Interpolate tint color between adjacent space colors
        let fractionalPage = -targetX / pageW
        let leftIndex = Int(floor(fractionalPage))
        let rightIndex = leftIndex + 1
        let fraction = fractionalPage - CGFloat(leftIndex)
        let spaces = relevantSpaces
        if leftIndex >= 0, rightIndex < spaces.count {
            let leftColor = spaces[leftIndex].color
            let rightColor = spaces[rightIndex].color
            if let blended = leftColor.blended(withFraction: fraction, of: rightColor) {
                view.layer?.backgroundColor = blended.withAlphaComponent(0.1).cgColor
            }
        } else if !spaces.isEmpty {
            // Edge rubber-band: use the edge space's color
            let edgeIndex = fractionalPage < 0 ? 0 : spaces.count - 1
            view.layer?.backgroundColor = spaces[edgeIndex].color.withAlphaComponent(0.1).cgColor
        }
    }

    private func handleSwipeEnd() {
        let pageW = pageClipView.bounds.width
        guard pageW > 0 else { return }

        let currentOffset = -pageStripView.frame.origin.x
        let fractionalPage = currentOffset / pageW

        // Snap to nearest page, biased toward the swipe direction
        let targetPage: Int
        if abs(swipeAccumulatedX) > pageW * 0.5 {
            if swipeAccumulatedX > 0 {
                targetPage = max(0, activePageIndex - 1)
            } else {
                targetPage = min(pageScrollViews.count - 1, activePageIndex + 1)
            }
        } else {
            targetPage = Int(round(fractionalPage)).clamped(to: 0...(max(0, pageScrollViews.count - 1)))
        }

        let targetX = -CGFloat(targetPage) * pageW
        let distance = abs(pageStripView.frame.origin.x - targetX)
        let duration = min(0.25, max(0.08, Double(distance / pageW) * 0.25))

        isAnimatingSwipe = true

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var frame = pageStripView.frame
            frame.origin.x = targetX
            pageStripView.animator().frame = frame
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.isAnimatingSwipe = false

            if targetPage != self.activePageIndex {
                let spaces = self.relevantSpaces
                guard targetPage < spaces.count else { return }
                self.delegate?.tabSidebarDidRequestSwitchToSpace(self, spaceID: spaces[targetPage].id)
            } else if let startColor = self.swipeStartTintColor {
                // Cancelled — restore original tint
                self.view.layer?.backgroundColor = startColor.withAlphaComponent(0.1).cgColor
            }
        })

        swipeAccumulatedX = 0
    }

    // MARK: - Helpers

    /// Returns the spaces relevant to this sidebar — only the incognito space in incognito mode,
    /// or only non-incognito spaces in regular mode.
    private var relevantSpaces: [Space] {
        if isIncognito {
            return TabStore.shared.spaces.filter { $0.isIncognito && $0.id == activeSpaceID }
        }
        return TabStore.shared.spaces.filter { !$0.isIncognito }
    }

    private func tabsForTableView(_ tv: NSTableView) -> [BrowserTab] {
        guard let index = pageTableViews.firstIndex(where: { $0 === tv }) else { return tabs }
        if index == activePageIndex { return tabs }
        let spaces = relevantSpaces
        guard index < spaces.count else { return [] }
        return spaces[index].tabs
    }

    private func tabsAndPinnedForTableView(_ tv: NSTableView) -> (pinned: [BrowserTab], normal: [BrowserTab]) {
        guard let index = pageTableViews.firstIndex(where: { $0 === tv }) else {
            return (pinnedTabs, tabs)
        }
        if index == activePageIndex { return (pinnedTabs, tabs) }
        let spaces = relevantSpaces
        guard index < spaces.count else { return ([], []) }
        return (spaces[index].pinnedTabs, spaces[index].tabs)
    }

    func reloadTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: rowForNormalTab(at: index)), columnIndexes: IndexSet(integer: 0))
    }

    func reloadPinnedTab(at index: Int) {
        guard index >= 0, index < pinnedTabs.count else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: rowForPinnedTab(at: index)), columnIndexes: IndexSet(integer: 0))
    }
}

// MARK: - NSTableViewDataSource

extension TabSidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        totalRowCount(forTableView: tableView)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard tableView === self.tableView else { return nil }
        switch sidebarRow(for: row) {
        case .pinnedTab, .normalTab:
            let item = NSPasteboardItem()
            item.setString(String(row), forType: tabReorderPasteboardType)
            return item
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        guard let row = rowIndexes.first,
              let rowView = tableView.rowView(atRow: row, makeIfNecessary: false),
              let cellView = rowView.view(atColumn: 0) as? NSView else { return }

        // The visual rounded-corner area extends 6pt beyond the cell on each side
        let visualRect = cellView.bounds.insetBy(dx: -6, dy: 1)
        let imageSize = visualRect.size

        let image = NSImage(size: imageSize)
        image.lockFocus()

        // Draw the rounded-corner background (matches hover style)
        let bgRect = NSRect(origin: .zero, size: imageSize)
        UIConstants.hoverBackgroundColor.setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

        // Draw cell content offset so it aligns within the background
        if let bitmapRep = cellView.bitmapImageRepForCachingDisplay(in: cellView.bounds) {
            cellView.cacheDisplay(in: cellView.bounds, to: bitmapRep)
            let cellOrigin = NSPoint(x: -visualRect.origin.x, y: -visualRect.origin.y)
            bitmapRep.draw(in: NSRect(origin: cellOrigin, size: cellView.bounds.size))
        }

        image.unlockFocus()

        // Replace the dragging item's image with our rounded-corner version
        session.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, _, _ in
            let origin = NSPoint(x: draggingItem.draggingFrame.origin.x - 6, y: draggingItem.draggingFrame.origin.y)
            draggingItem.setDraggingFrame(NSRect(origin: origin, size: imageSize), contents: image)
        }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropOperation == .above else { return [] }

        let destRow = sidebarRow(for: row)

        switch destRow {
        case .topSpacer:
            // Retarget: dropping on spacer = first pinned tab position
            tableView.setDropRow(rowForPinnedTab(at: 0), dropOperation: .above)
        case .separator:
            // Retarget: dropping above separator = appending to pinned section
            tableView.setDropRow(1 + pinnedTabs.count, dropOperation: .above)
        case .newTab:
            // Retarget: dropping above newTab = prepending to normal section
            tableView.setDropRow(rowForNormalTab(at: 0), dropOperation: .above)
        default:
            break
        }

        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let rowString = item.string(forType: tabReorderPasteboardType),
              let sourceRow = Int(rowString) else { return false }

        let sourceSection = sidebarRow(for: sourceRow)
        var destSection = sidebarRow(for: row)

        // Remap non-droppable rows to the nearest section edge
        switch destSection {
        case .topSpacer:
            destSection = .pinnedTab(index: 0)
        case .separator:
            destSection = .pinnedTab(index: pinnedTabs.count)
        case .newTab:
            destSection = .normalTab(index: 0)
        default:
            break
        }

        suppressReload = true
        defer { suppressReload = false }

        switch (sourceSection, destSection) {
        case (.pinnedTab(let srcIdx), .pinnedTab(let dstIdx)):
            let adjustedDest = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
            guard srcIdx != adjustedDest else { return false }
            tableView.beginUpdates()
            tableView.moveRow(at: sourceRow, to: row > sourceRow ? row - 1 : row)
            tableView.endUpdates()
            delegate?.tabSidebar(self, didMovePinnedTabFrom: srcIdx, to: adjustedDest)
            return true

        case (.normalTab(let srcIdx), .normalTab(let dstIdx)):
            let adjustedDest = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
            guard srcIdx != adjustedDest else { return false }
            tableView.beginUpdates()
            tableView.moveRow(at: sourceRow, to: row > sourceRow ? row - 1 : row)
            tableView.endUpdates()
            delegate?.tabSidebar(self, didMoveTabFrom: srcIdx, to: dstIdx)
            return true

        case (.normalTab(let srcIdx), .pinnedTab(let dstIdx)):
            let oldSourceRow = rowForNormalTab(at: srcIdx)

            // Update data model (reload stays suppressed via setTabs)
            delegate?.tabSidebar(self, didDragTabToPinAt: srcIdx, destinationIndex: dstIdx)

            tableView.beginUpdates()
            tableView.moveRow(at: oldSourceRow, to: rowForPinnedTab(at: dstIdx))
            tableView.endUpdates()
            return true

        case (.pinnedTab(let srcIdx), .normalTab(let dstIdx)):
            let oldSourceRow = rowForPinnedTab(at: srcIdx)

            // Update data model (reload stays suppressed via setTabs)
            delegate?.tabSidebar(self, didDragPinnedTabToUnpinAt: srcIdx, destinationIndex: dstIdx)

            tableView.beginUpdates()
            tableView.moveRow(at: oldSourceRow, to: rowForNormalTab(at: dstIdx))
            tableView.endUpdates()
            return true

        default:
            return false
        }
    }
}

// MARK: - NSTableViewDelegate

extension TabSidebarViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (pinned, _) = tabsAndPinnedForTableView(tableView)
        let sRow = sidebarRow(for: row, pinnedCount: pinned.count)
        let isActive = tableView === self.tableView

        switch sRow {
        case .topSpacer:
            return NSView()
        case .newTab:
            let newTabID = NSUserInterfaceItemIdentifier("NewTabCell")
            if let existing = tableView.makeView(withIdentifier: newTabID, owner: nil) as? NewTabCellView {
                return existing
            }
            let cell = NewTabCellView()
            cell.identifier = newTabID
            return cell

        case .separator:
            let sepID = NSUserInterfaceItemIdentifier("SeparatorCell")
            if let existing = tableView.makeView(withIdentifier: sepID, owner: nil) as? SeparatorCellView {
                return existing
            }
            let cell = SeparatorCellView()
            cell.identifier = sepID
            return cell

        case .pinnedTab(let index):
            guard index < pinned.count else { return makeTabCell(tableView) }
            let tab = pinned[index]
            let cell = makeTabCell(tableView)
            configureTabCell(cell, tab: tab, title: tab.pinnedDisplayTitle, pinnedTab: tab, isActive: isActive) { [weak self] row in
                guard let self, case .pinnedTab(let idx) = self.sidebarRow(for: row) else { return }
                self.delegate?.tabSidebar(self, didRequestClosePinnedTabAt: idx)
            }
            return cell

        case .normalTab(let tabIndex):
            let tabsForTable = tabsForTableView(tableView)
            guard tabIndex < tabsForTable.count else { return makeTabCell(tableView) }
            let tab = tabsForTable[tabIndex]
            let cell = makeTabCell(tableView)
            configureTabCell(cell, tab: tab, title: tab.title, pinnedTab: nil, isActive: isActive) { [weak self] row in
                guard let self, case .normalTab(let idx) = self.sidebarRow(for: row) else { return }
                self.delegate?.tabSidebar(self, didRequestCloseTabAt: idx)
            }
            return cell
        }
    }

    private func makeTabCell(_ tableView: NSTableView) -> TabCellView {
        let cellID = NSUserInterfaceItemIdentifier("TabCell")
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? TabCellView {
            return existing
        }
        let cell = TabCellView()
        cell.identifier = cellID
        return cell
    }

    private func configureTabCell(_ cell: TabCellView, tab: BrowserTab, title: String, pinnedTab: BrowserTab?, isActive: Bool, onClose: @escaping (Int) -> Void) {
        cell.titleLabel.stringValue = title
        cell.toolTip = tab.title
        cell.updateFavicon(tab.favicon)
        cell.updateSleeping(tab.isSleeping)
        cell.updateLoading(tab.isLoading)
        cell.updateProgress(tab.estimatedProgress)
        cell.updateAudio(isPlaying: tab.isPlayingAudio, isMuted: tab.isMuted)
        cell.updatePinnedMode(tab: pinnedTab)
        if isActive {
            cell.onClose = { [weak self] in
                guard let self else { return }
                let row = self.tableView.row(for: cell)
                guard row >= 0 else { return }
                onClose(row)
            }
            cell.onToggleMute = { tab.toggleMute() }
        } else {
            cell.onClose = nil
            cell.onToggleMute = nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let (pinned, _) = tabsAndPinnedForTableView(tableView)
        switch sidebarRow(for: row, pinnedCount: pinned.count) {
        case .topSpacer: return 2
        case .separator: return 12
        default: return 36
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let (pinned, _) = tabsAndPinnedForTableView(tableView)
        switch sidebarRow(for: row, pinnedCount: pinned.count) {
        case .topSpacer, .newTab, .separator:
            return NSTableRowView()
        default:
            let rowView = TabRowView()
            rowView.selectionColor = tintColor
            return rowView
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let (pinned, _) = tabsAndPinnedForTableView(tableView)
        switch sidebarRow(for: row, pinnedCount: pinned.count) {
        case .topSpacer, .separator: return false
        default: return true
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let notifyingTable = notification.object as? NSTableView,
              notifyingTable === tableView else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }

        switch sidebarRow(for: row) {
        case .newTab:
            tableView.deselectRow(row)
            delegate?.tabSidebarDidRequestNewTab(self)
        case .pinnedTab(let index):
            delegate?.tabSidebar(self, didSelectPinnedTabAt: index)
        case .normalTab(let index):
            delegate?.tabSidebar(self, didSelectTabAt: index)
        case .topSpacer, .separator:
            break
        }
    }
}

// MARK: - Context Menu

extension TabSidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }

        let row = sidebarRow(for: clickedRow)
        let tabIndex: Int
        let isPinned: Bool

        switch row {
        case .pinnedTab(let index):
            tabIndex = index
            isPinned = true
        case .normalTab(let index):
            tabIndex = index
            isPinned = false
        default:
            return
        }

        contextMenuTabIndex = tabIndex
        contextMenuTabIsPinned = isPinned

        let tab = isPinned ? pinnedTabs[tabIndex] : tabs[tabIndex]
        let isSelectedTab = clickedRow == tableView.selectedRow

        // Copy URL / Copy Link
        if tab.url != nil {
            let copyItem = NSMenuItem(
                title: isSelectedTab ? "Copy URL" : "Copy Link",
                action: #selector(contextMenuCopyURL(_:)),
                keyEquivalent: isSelectedTab ? "C" : ""
            )
            if isSelectedTab {
                copyItem.keyEquivalentModifierMask = [.command, .shift]
            }
            copyItem.target = self
            menu.addItem(copyItem)
        }

        // Share submenu
        if let url = tab.url {
            let shareItem = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
            let shareMenu = NSMenu()
            for service in NSSharingService.sharingServices(forItems: [url]) {
                let serviceItem = NSMenuItem(title: service.title, action: #selector(contextMenuShare(_:)), keyEquivalent: "")
                serviceItem.target = self
                serviceItem.representedObject = service
                serviceItem.image = service.image
                shareMenu.addItem(serviceItem)
            }
            shareItem.submenu = shareMenu
            menu.addItem(shareItem)
        }

        menu.addItem(.separator())

        // Duplicate
        if tab.url != nil {
            let dupItem = NSMenuItem(title: "Duplicate", action: #selector(contextMenuDuplicate(_:)), keyEquivalent: "")
            dupItem.target = self
            menu.addItem(dupItem)
        }

        // Move to Space submenu
        let spaces = delegate?.tabSidebarSpacesForContextMenu(self) ?? []
        if spaces.count > 1 {
            let moveItem = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            let moveMenu = NSMenu()
            for space in spaces {
                let spaceItem = NSMenuItem(
                    title: "\(space.emoji) \(space.name)",
                    action: #selector(contextMenuMoveToSpace(_:)),
                    keyEquivalent: ""
                )
                spaceItem.target = self
                spaceItem.representedObject = space.id
                if space.isCurrent {
                    spaceItem.state = .on
                }
                moveMenu.addItem(spaceItem)
            }
            moveItem.submenu = moveMenu
            menu.addItem(moveItem)
        }

        menu.addItem(.separator())

        if isPinned {
            let unpinItem = NSMenuItem(title: "Unpin Tab", action: #selector(contextMenuUnpinTab(_:)), keyEquivalent: "")
            unpinItem.target = self
            menu.addItem(unpinItem)
        } else {
            if tab.url != nil {
                let pinItem = NSMenuItem(title: "Pin Tab", action: #selector(contextMenuPinTab(_:)), keyEquivalent: "")
                pinItem.target = self
                menu.addItem(pinItem)
            }

            let archiveItem = NSMenuItem(title: "Archive Tab", action: #selector(contextMenuArchiveTab(_:)), keyEquivalent: "")
            archiveItem.target = self
            menu.addItem(archiveItem)

            let archiveBelowItem = NSMenuItem(title: "Archive Tabs Below", action: #selector(contextMenuArchiveTabsBelow(_:)), keyEquivalent: "")
            archiveBelowItem.target = self
            if tabIndex >= tabs.count - 1 {
                archiveBelowItem.isEnabled = false
            }
            menu.addItem(archiveBelowItem)
        }
    }

    @objc private func contextMenuCopyURL(_ sender: NSMenuItem) {
        let tab = contextMenuTabIsPinned ? pinnedTabs[contextMenuTabIndex] : tabs[contextMenuTabIndex]
        guard let url = tab.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func contextMenuShare(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? NSSharingService else { return }
        let tab = contextMenuTabIsPinned ? pinnedTabs[contextMenuTabIndex] : tabs[contextMenuTabIndex]
        guard let url = tab.url else { return }
        service.perform(withItems: [url])
    }

    @objc private func contextMenuDuplicate(_ sender: NSMenuItem) {
        delegate?.tabSidebar(self, didRequestDuplicateTabAt: contextMenuTabIndex, isPinned: contextMenuTabIsPinned)
    }

    @objc private func contextMenuMoveToSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? UUID else { return }
        delegate?.tabSidebar(self, didRequestMoveTabAt: contextMenuTabIndex, isPinned: contextMenuTabIsPinned, toSpaceID: spaceID)
    }

    @objc private func contextMenuPinTab(_ sender: NSMenuItem) {
        delegate?.tabSidebar(self, didRequestPinTabAt: contextMenuTabIndex)
    }

    @objc private func contextMenuUnpinTab(_ sender: NSMenuItem) {
        delegate?.tabSidebar(self, didRequestUnpinTabAt: contextMenuTabIndex)
    }

    @objc private func contextMenuArchiveTab(_ sender: NSMenuItem) {
        delegate?.tabSidebar(self, didRequestArchiveTabAt: contextMenuTabIndex)
    }

    @objc private func contextMenuArchiveTabsBelow(_ sender: NSMenuItem) {
        delegate?.tabSidebar(self, didRequestArchiveTabsBelowIndex: contextMenuTabIndex)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
