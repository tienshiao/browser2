import AppKit

protocol FindBarDelegate: AnyObject {
    func findBar(_ bar: FindBarView, searchFor text: String, backwards: Bool)
    func findBarDidDismiss(_ bar: FindBarView)
}

class FindBarView: NSView {
    weak var delegate: FindBarDelegate?

    let searchField = NSTextField()
    private let previousButton = HoverButton()
    private let nextButton = HoverButton()
    private let resultLabel = NSTextField(labelWithString: "")
    private let doneButton = HoverButton()
    private var effectView: NSVisualEffectView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        searchField.placeholderString = "Find in Page"
        searchField.font = .boldSystemFont(ofSize: 13)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none

        let boldConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)

        previousButton.bezelStyle = .inline
        previousButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")?.withSymbolConfiguration(boldConfig)
        previousButton.circular = true
        previousButton.target = self
        previousButton.action = #selector(previousClicked(_:))
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.isBordered = false

        nextButton.bezelStyle = .inline
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")?.withSymbolConfiguration(boldConfig)
        nextButton.circular = true
        nextButton.target = self
        nextButton.action = #selector(nextClicked(_:))
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.isBordered = false

        resultLabel.font = .systemFont(ofSize: 12)
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        doneButton.bezelStyle = .inline
        doneButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Done")?.withSymbolConfiguration(boldConfig)
        doneButton.circular = true
        doneButton.isBordered = false
        doneButton.target = self
        doneButton.action = #selector(doneClicked(_:))
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.keyEquivalent = "\u{1b}" // Escape

        let stack = NSStackView(views: [searchField, previousButton, nextButton, resultLabel, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        translatesAutoresizingMaskIntoConstraints = false

        let container: NSView

        if #available(macOS 26.0, *) {
            stack.edgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
            let glass = NSGlassEffectView()
            glass.cornerRadius = .infinity
            glass.translatesAutoresizingMaskIntoConstraints = false
            let paddingView = NSView()
            paddingView.translatesAutoresizingMaskIntoConstraints = false
            paddingView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: paddingView.topAnchor, constant: 10),
                stack.bottomAnchor.constraint(equalTo: paddingView.bottomAnchor, constant: -10),
                stack.leadingAnchor.constraint(equalTo: paddingView.leadingAnchor, constant: 14),
                stack.trailingAnchor.constraint(equalTo: paddingView.trailingAnchor, constant: -14),
            ])
            glass.contentView = paddingView
            addSubview(glass)
            container = glass
        } else {
            let shadowContainer = NSView()
            shadowContainer.wantsLayer = true
            shadowContainer.shadow = NSShadow()
            shadowContainer.layer?.shadowColor = NSColor.black.cgColor
            shadowContainer.layer?.shadowOpacity = 0.5
            shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
            shadowContainer.layer?.shadowRadius = 20
            shadowContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(shadowContainer)

            let ev = NSVisualEffectView()
            ev.material = .hudWindow
            ev.blendingMode = .withinWindow
            ev.state = .active
            ev.wantsLayer = true
            ev.layer?.masksToBounds = true
            ev.layer?.borderWidth = 0.5
            ev.layer?.borderColor = NSColor.separatorColor.cgColor
            ev.translatesAutoresizingMaskIntoConstraints = false
            shadowContainer.addSubview(ev)
            ev.addSubview(stack)
            self.effectView = ev

            NSLayoutConstraint.activate([
                shadowContainer.topAnchor.constraint(equalTo: topAnchor),
                shadowContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                shadowContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                shadowContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

                ev.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
                ev.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),
                ev.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
                ev.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),

                stack.topAnchor.constraint(equalTo: ev.topAnchor),
                stack.bottomAnchor.constraint(equalTo: ev.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: ev.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: ev.trailingAnchor),

                searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            ])
            return
        }

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),

            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    override func layout() {
        super.layout()
        effectView?.layer?.cornerRadius = bounds.height / 2
    }

    func focus() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func updateResultLabel(_ text: String) {
        resultLabel.stringValue = text
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: NSTextField) {
        let text = sender.stringValue
        if text.isEmpty {
            resultLabel.stringValue = ""
        } else {
            delegate?.findBar(self, searchFor: text, backwards: false)
        }
    }

    @objc private func previousClicked(_ sender: Any?) {
        let text = searchField.stringValue
        guard !text.isEmpty else { return }
        delegate?.findBar(self, searchFor: text, backwards: true)
    }

    @objc private func nextClicked(_ sender: Any?) {
        let text = searchField.stringValue
        guard !text.isEmpty else { return }
        delegate?.findBar(self, searchFor: text, backwards: false)
    }

    @objc private func doneClicked(_ sender: Any?) {
        delegate?.findBarDidDismiss(self)
    }
}

extension FindBarView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let text = searchField.stringValue
        if text.isEmpty {
            resultLabel.stringValue = ""
        } else {
            delegate?.findBar(self, searchFor: text, backwards: false)
        }
    }
}
