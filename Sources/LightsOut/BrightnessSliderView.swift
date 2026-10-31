import AppKit

/// A brightness row laid out on the menu's own columns: the sun sits where checkmarks go, the slider starts where
/// item titles start, and the percentage ends where keyboard shortcuts end.
final class BrightnessSliderView: NSView {
    var onChange: ((Double) -> Void)?

    private let nameLabel: NSTextField?
    private let icon = NSImageView()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let percentLabel = NSTextField(labelWithString: "")

    /// Standard menu item geometry, measured from the view-based menus of macOS 26 and later. Earlier versions draw
    /// menus with narrower margins.
    private enum Metrics {
        static let modern = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        /// Leading edge of the checkmark column.
        static let stateX: CGFloat = modern ? 12 : 8
        /// Where item titles' glyphs start. Our labels draw flush with their frames, so they go right here.
        static let titleX: CGFloat = modern ? 30 : 22
        /// Distance from the trailing edge to where keyboard shortcuts end.
        static let trailing: CGFloat = modern ? 18 : 16
    }

    /// - Parameter name: Shown above the slider; pass nil when the section header already identifies the display.
    init(name: String?, level: Double) {
        nameLabel = name.map { NSTextField(labelWithString: $0) }
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: name == nil ? 28 : 44))
        // The menu stretches the view to its own width.
        autoresizingMask = [.width]

        icon.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor

        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.setAccessibilityLabel(name.map { "\($0) brightness" } ?? "Brightness")

        percentLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right

        var views: [NSView] = [icon, slider, percentLabel]
        if let nameLabel {
            nameLabel.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
            nameLabel.textColor = .secondaryLabelColor
            nameLabel.lineBreakMode = .byTruncatingTail
            views.append(nameLabel)
        }
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let rowCenter = name == nil ? centerYAnchor : bottomAnchor
        let rowOffset: CGFloat = name == nil ? 0 : -14
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.stateX),
            icon.centerYAnchor.constraint(equalTo: rowCenter, constant: rowOffset),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.titleX),
            slider.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            slider.trailingAnchor.constraint(equalTo: percentLabel.leadingAnchor, constant: -8),

            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.trailing),
            percentLabel.firstBaselineAnchor.constraint(equalTo: slider.centerYAnchor, constant: 4),
            // Wide enough for "100%", so the slider doesn't shift as the value changes.
            percentLabel.widthAnchor.constraint(equalToConstant: 38),
        ])
        if let nameLabel {
            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.titleX),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Metrics.trailing),
                nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            ])
        }

        self.level = level
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var level: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = newValue
            updatePercent()
        }
    }

    var isEnabled: Bool {
        get { slider.isEnabled }
        set {
            slider.isEnabled = newValue
            let color: NSColor = newValue ? .secondaryLabelColor : .tertiaryLabelColor
            [nameLabel, percentLabel].forEach { $0?.textColor = color }
            icon.contentTintColor = color
        }
    }

    @objc private func sliderMoved() {
        updatePercent()
        onChange?(slider.doubleValue)
    }

    private func updatePercent() {
        percentLabel.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
    }
}
