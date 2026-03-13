import AppKit
import WebKit

class PeekOverlayView: NSView {
    let peekWebView: WKWebView
    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?

    private let shadowContainer = NSView()
    private let panelView = NSView()
    private let closeButton: NSButton
    private let expandButton: NSButton

    init(peekWebView: WKWebView) {
        self.peekWebView = peekWebView
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!.withSymbolConfiguration(symbolConfig)!,
            target: nil,
            action: nil
        )
        expandButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right.circle.fill", accessibilityDescription: "Open in New Tab")!.withSymbolConfiguration(symbolConfig)!,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true

        // Shadow container (casts shadow, no clipping)
        shadowContainer.wantsLayer = true
        shadowContainer.shadow = NSShadow()
        shadowContainer.layer?.shadowColor = NSColor.black.cgColor
        shadowContainer.layer?.shadowOpacity = 0.5
        shadowContainer.layer?.shadowRadius = 30
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: -5)
        shadowContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowContainer)

        // Panel (clips corners)
        panelView.wantsLayer = true
        panelView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panelView.layer?.cornerRadius = 12
        panelView.layer?.masksToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.addSubview(panelView)

        // WebView inside panel
        peekWebView.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(peekWebView)

        // Buttons
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.contentTintColor = .labelColor
        addSubview(closeButton)

        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.target = self
        expandButton.action = #selector(expandTapped)
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.contentTintColor = .labelColor
        addSubview(expandButton)

        NSLayoutConstraint.activate([
            // Shadow container: fixed margins from overlay edges
            shadowContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            shadowContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            shadowContainer.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            shadowContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            // Panel fills shadow container
            panelView.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            panelView.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
            panelView.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),

            // WebView fills panel
            peekWebView.topAnchor.constraint(equalTo: panelView.topAnchor),
            peekWebView.bottomAnchor.constraint(equalTo: panelView.bottomAnchor),
            peekWebView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            peekWebView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),

            // Buttons: vertical stack to the right of the panel, aligned to top
            closeButton.leadingAnchor.constraint(equalTo: shadowContainer.trailingAnchor, constant: 4),
            closeButton.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            expandButton.leadingAnchor.constraint(equalTo: shadowContainer.trailingAnchor, constant: 4),
            expandButton.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            expandButton.widthAnchor.constraint(equalToConstant: 32),
            expandButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func expandTapped() {
        onExpand?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always claim the hit so clicks never pass through to the underlying web view
        return super.hitTest(point) ?? self
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward scrolls inside the panel to the peek web view, swallow the rest
        let point = convert(event.locationInWindow, from: nil)
        if shadowContainer.frame.contains(point) {
            peekWebView.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Clicking outside the panel closes the peek
        let point = convert(event.locationInWindow, from: nil)
        if !shadowContainer.frame.contains(point) {
            onClose?()
        }
    }
}
