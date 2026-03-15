import AppKit

class ToastManager {
    weak var parentView: NSView?
    private var currentToast: ToastView?
    private var hideGeneration = 0

    func show(message: String) {
        guard let parent = parentView else { return }

        currentToast?.removeFromSuperview()

        let toast = ToastView()
        toast.label.stringValue = message
        toast.alphaValue = 0
        parent.addSubview(toast)
        currentToast = toast

        NSLayoutConstraint.activate([
            toast.topAnchor.constraint(equalTo: parent.topAnchor, constant: 12),
            toast.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -12),
        ])

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            toast.animator().alphaValue = 1
        }

        hideGeneration &+= 1
        let gen = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.hideGeneration == gen else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.hideGeneration == gen else { return }
                toast.removeFromSuperview()
                if self.currentToast === toast { self.currentToast = nil }
            })
        }
    }
}

class ToastView: NSView {
    fileprivate let label = NSTextField(labelWithString: "")
    private var effectView: NSVisualEffectView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        translatesAutoresizingMaskIntoConstraints = false

        let container: NSView

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = .infinity
            glass.translatesAutoresizingMaskIntoConstraints = false
            let paddingView = NSView()
            paddingView.translatesAutoresizingMaskIntoConstraints = false
            paddingView.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: paddingView.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: paddingView.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: paddingView.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: paddingView.trailingAnchor, constant: -14),
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
            ev.addSubview(label)
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

                label.topAnchor.constraint(equalTo: ev.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: ev.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: ev.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: ev.trailingAnchor, constant: -14),
            ])
            return
        }

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func layout() {
        super.layout()
        effectView?.layer?.cornerRadius = bounds.height / 2
    }
}
