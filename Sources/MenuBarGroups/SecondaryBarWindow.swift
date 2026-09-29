import AppKit

/// A sleek floating sub-bar that appears beneath the menu bar to show grouped or hidden items.
@MainActor
public final class SecondaryBarWindow: NSPanel {
    private let visualEffectView = NSVisualEffectView()
    private let stackView = NSStackView()
    private var onSelect: ((MenuBarItem) -> Void)?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.transient, .ignoresCycle]

        setupView()
    }

    private func setupView() {
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 10
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        visualEffectView.layer?.borderWidth = 1

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        contentView = visualEffectView
    }

    /// Updates the items displayed in the secondary sub-bar.
    public func update(items: [MenuBarItem], onSelect: @escaping (MenuBarItem) -> Void) {
        self.onSelect = onSelect
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if items.isEmpty {
            let label = NSTextField(labelWithString: "No items in group")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(label)
        } else {
            for item in items {
                let button = createItemButton(for: item)
                stackView.addArrangedSubview(button)
            }
        }

        stackView.layoutSubtreeIfNeeded()
        let fitting = stackView.fittingSize
        setContentSize(NSSize(width: max(fitting.width, 100), height: 42))
    }

    private func createItemButton(for item: MenuBarItem) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.isBordered = false
        button.image = IconManager.shared.icon(for: item)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = "\(item.name) (Click to open menu)"
        button.target = self
        button.action = #selector(itemClicked(_:))

        // Custom hover effect
        button.wantsLayer = true
        button.layer?.cornerRadius = 6

        // Store item in button layer identifier or tag mapping
        objc_setAssociatedObject(button, "menuBarItem", item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])

        return button
    }

    @objc private func itemClicked(_ sender: NSButton) {
        if let item = objc_getAssociatedObject(sender, "menuBarItem") as? MenuBarItem {
            orderOut(nil)
            onSelect?(item)
        }
    }

    /// Positions the sub-bar beneath an anchor status item button.
    public func show(beneath button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(buttonRect)

        let barSize = frame.size
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        // Center horizontally with button, clamped to screen bounds
        let preferredX = screenRect.midX - (barSize.width / 2)
        let clampedX = min(max(preferredX, visibleFrame.minX + 8), visibleFrame.maxX - barSize.width - 8)
        let targetY = screenRect.minY - barSize.height - 4

        setFrameOrigin(NSPoint(x: clampedX, y: targetY))
        makeKeyAndOrderFront(nil)
    }

    public override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
