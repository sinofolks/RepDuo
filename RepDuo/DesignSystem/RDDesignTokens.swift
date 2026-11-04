import UIKit

enum RDColor {
    /// Grouped screen background.
    static let background = dynamic(light: 0xF2F2F7, dark: 0x000000)
    /// Cards and grouped rows on `background`.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Tracks, unfilled bars, and inset controls.
    static let fill = dynamic(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let label = dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let secondaryLabel = dynamic(light: 0x6C6C70, dark: 0x98989F)
    /// Non-essential text only; it does not meet 4.5:1 on cards.
    static let tertiaryLabel = dynamic(light: 0x8A8A8E, dark: 0x7C7C82)
    static let separator = dynamic(light: 0xC6C6C8, dark: 0x38383A)
    /// The app's one accent: primary actions, progress, active state.
    static let accent = dynamic(light: 0x248A3D, dark: 0x30D158)
    /// Text and symbols drawn on `accent`.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let accentTint = UIColor { traits in
        accent.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.2 : 0.12)
    }
    /// Camera stages stay black in either appearance.
    static let camera = UIColor(hex: 0x000000)
    static let warning = dynamic(light: 0xC75300, dark: 0xFF9F0A)
    static let destructive = dynamic(light: 0xD70015, dark: 0xFF453A)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

enum RDSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Shape rule: cards and grouped sections 12, buttons 14, inner tiles 8,
/// tags and pills are capsules. All corners are continuous.
enum RDCornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 14
}

enum RDLayout {
    static let screenMargin: CGFloat = 16
}

enum RDFont {
    /// SF Pro Rounded with tabular digits for counts, scores, and times.
    static func numeric(
        _ size: CGFloat,
        weight: UIFont.Weight = .bold,
        maximumScale: CGFloat = 1.25
    ) -> UIFont {
        let scaled = min(UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: size), size * maximumScale)
        let base = UIFont.systemFont(ofSize: scaled, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        descriptor = descriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: descriptor, size: scaled)
    }

    /// Section header above grouped content, such as "Pick your move".
    static func eyebrow(_ size: CGFloat = 13) -> UIFont {
        UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: size, weight: .regular),
            maximumPointSize: size * 1.6
        )
    }

    static func display(_ size: CGFloat) -> UIFont {
        UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: size, weight: .bold),
            maximumPointSize: size * 1.25
        )
    }

    static func title(_ size: CGFloat = 28) -> UIFont {
        UIFontMetrics(forTextStyle: .title1).scaledFont(
            for: .systemFont(ofSize: size, weight: .bold),
            maximumPointSize: size * 1.35
        )
    }

    static func body(weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.preferredFont(forTextStyle: .body).withWeight(weight)
    }

    static func caption(weight: UIFont.Weight = .semibold) -> UIFont {
        UIFont.preferredFont(forTextStyle: .caption1).withWeight(weight)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension UILabel {
    func setEyebrow(_ text: String, color: UIColor = RDColor.secondaryLabel) {
        self.text = text
        font = RDFont.eyebrow()
        textColor = color
        adjustsFontForContentSizeCategory = true
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

extension UIView {
    /// Continuous ("squircle") corners, the shape iOS uses for its own surfaces.
    func setContinuousCorners(_ radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
    }

    func pinEdges(to other: UIView, insets: NSDirectionalEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.leading),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.trailing),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

extension UIStackView {
    convenience init(axis: NSLayoutConstraint.Axis, spacing: CGFloat, arrangedSubviews: [UIView] = []) {
        self.init(arrangedSubviews: arrangedSubviews)
        self.axis = axis
        self.spacing = spacing
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}
