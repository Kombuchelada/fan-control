import AppKit

/// A non-interactive menu row showing a label and a right-aligned live value,
/// laid out to line up with the titles of standard menu items.
final class MenuReadingView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    /// Horizontal positions matching AppKit's layout of standard items that have both
    /// a state column and an image (measured on macOS 26).
    static let iconCenterX: CGFloat = 32
    static let iconWidth: CGFloat = 16
    static let titleLeading: CGFloat = 46
    static let trailingInset: CGFloat = 16
    static let height: CGFloat = 22

    var value: String {
        get { valueField.stringValue }
        set { valueField.stringValue = newValue }
    }

    init(title: String, symbol: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: Self.height))
        autoresizingMask = [.width]

        let font = NSFont.menuFont(ofSize: 0)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown

        titleField.stringValue = title
        titleField.font = font
        titleField.textColor = .labelColor

        valueField.font = .monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        valueField.textColor = .secondaryLabelColor
        valueField.alignment = .right

        for view in [iconView, titleField, valueField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        titleField.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Self.iconCenterX),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconWidth),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleLeading),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 24),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityLabel() -> String? {
        "\(titleField.stringValue), \(valueField.stringValue)"
    }
}
