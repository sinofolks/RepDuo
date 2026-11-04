import UIKit

enum RDColor {
    static let background = UIColor(hex: 0x07080A)
    /// Camera stages: pure black so the neon body reads as the only light source.
    static let backgroundDeep = UIColor(hex: 0x000000)
    static let surface = UIColor(hex: 0x111317)
    static let surfaceRaised = UIColor(hex: 0x15171B)
    static let surfaceSecondary = UIColor(hex: 0x1E2126)
    static let neonGreen = UIColor(hex: 0xC8FF1F)
    static let neonBright = UIColor(hex: 0xE2FF7A)
    /// Selected-card fill behind lime content.
    static let neonTint = UIColor(hex: 0x12160A)
    /// Streaks, personal bests, and heart rate.
    static let ember = UIColor(hex: 0xFF6A2B)
    static let warmWhite = UIColor(hex: 0xF5F6F2)
    static let textBody = UIColor(hex: 0xC9CCD1)
    static let textSecondary = UIColor(hex: 0x9CA1A9)
    static let textMuted = UIColor(hex: 0x80868F)
    static let separatorOnDark = UIColor(hex: 0x262A31)
    static let separatorStrong = UIColor(hex: 0x3A3F47)
    static let warning = UIColor(hex: 0xFFB020)
    static let destructive = UIColor(hex: 0xFF7A7A)
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
    static let small: CGFloat = 4
    static let medium: CGFloat = 6
    static let large: CGFloat = 8
}

enum RDLayout {
    static let screenMargin: CGFloat = 20
    /// Horizontal run of the parallelogram cut on primary buttons and tags.
    static let slant: CGFloat = 12
}

enum RDFont {
    /// Condensed, italic system numerals for counts, scores, and scoreboard-style labels.
    static func numeric(
        _ size: CGFloat,
        weight: UIFont.Weight = .black,
        italic: Bool = true,
        maximumScale: CGFloat = 1.25
    ) -> UIFont {
        // UIFontMetrics.scaledFont drops the width trait, so scale the size and build the font directly.
        let scaled = min(UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: size), size * maximumScale)
        return condensedSystemFont(ofSize: scaled, weight: weight, italic: italic)
    }

    /// Letter-spaced condensed caption above headings, such as "PICK YOUR MOVE".
    static func eyebrow(_ size: CGFloat = 14) -> UIFont {
        let scaled = min(UIFontMetrics(forTextStyle: .caption1).scaledValue(for: size), size * 1.4)
        return condensedSystemFont(ofSize: scaled, weight: .heavy, italic: false)
    }

    private static func condensedSystemFont(ofSize size: CGFloat, weight: UIFont.Weight, italic: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        guard italic else { return base }
        // Condensed SF has no true italic; rebuilding traits falls back to the regular width,
        // so lean the condensed face with a shear matrix instead.
        let shear = CGAffineTransform(a: 1, b: 0, c: tan(.pi / 15), d: 1, tx: 0, ty: 0)
        return UIFont(descriptor: base.fontDescriptor.addingAttributes([.matrix: shear]), size: size)
    }

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

extension UIBezierPath {
    /// Parallelogram with both vertical edges leaning right, used for the
    /// competitive "cut" on buttons, tags, and bars.
    static func rdSlanted(in rect: CGRect, slant: CGFloat = RDLayout.slant) -> UIBezierPath {
        let inset = min(slant, rect.width / 4)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }
}

extension UILabel {
    func setEyebrow(_ text: String, color: UIColor = RDColor.textSecondary, kern: CGFloat = 2) {
        attributedText = NSAttributedString(string: text, attributes: [.kern: kern])
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
