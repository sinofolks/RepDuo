import UIKit

enum RDColor {
    static let background = UIColor(hex: 0x171A1F)
    static let backgroundDeep = UIColor(hex: 0x101317)
    static let surface = UIColor(hex: 0x22262C)
    static let surfaceSecondary = UIColor(hex: 0x24282E)
    static let neonGreen = UIColor(hex: 0xB4F20B)
    static let neonBright = UIColor(hex: 0xD7FF57)
    static let warmWhite = UIColor(hex: 0xF8F8F4)
    static let textSecondary = UIColor(hex: 0xA7ABB1)
    static let textMuted = UIColor(hex: 0x60646B)
    static let separator = UIColor(hex: 0xD8D9D4)
    static let separatorOnDark = UIColor(hex: 0x3B4048)
    static let warning = UIColor(hex: 0xFFCB66)
    static let destructive = UIColor(hex: 0xFF6B6B)
}

enum RDSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum RDCornerRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
}

enum RDFont {
    static func display(_ size: CGFloat) -> UIFont {
        UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: size, weight: .black),
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

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

extension UIView {
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

extension UIStackView {
    convenience init(axis: NSLayoutConstraint.Axis, spacing: CGFloat, arrangedSubviews: [UIView] = []) {
        self.init(arrangedSubviews: arrangedSubviews)
        self.axis = axis
        self.spacing = spacing
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}
