import AppKit

/// A menu row with a display's name over a brightness slider, in the style of Control Center.
final class BrightnessSliderView: NSView {
    var onChange: ((Double) -> Void)?

    private let label: NSTextField
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)

    init(name: String, level: Double) {
        label = NSTextField(labelWithString: name)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 48))

        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail

        slider.doubleValue = level
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.setAccessibilityLabel("\(name) brightness")

        let dim = Self.icon("sun.min")
        let bright = Self.icon("sun.max")
        let row = NSStackView(views: [dim, slider, bright])
        row.spacing = 6

        let column = NSStackView(views: [label, row])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var level: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue }
    }

    var isEnabled: Bool {
        get { slider.isEnabled }
        set {
            slider.isEnabled = newValue
            label.textColor = newValue ? .secondaryLabelColor : .tertiaryLabelColor
        }
    }

    @objc private func sliderMoved() {
        onChange?(slider.doubleValue)
    }

    private static func icon(_ symbol: String) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
}
