import UIKit
import SwiftUI

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

/// Key colours (docs/DESIGN.md §5). From iOS 26 each key is a piece of
/// Liquid Glass over the system's translucent keyboard backdrop, tinted with
/// the palette; the accent key carries the palette's full colour. Earlier
/// systems have no Liquid Glass (`liquid` is false): the keys are solid, in
/// the palette's tone, with the shadow under each key that keyboards had
/// then. With Reduce Transparency or Increase Contrast (`opaque`) the keys
/// are solid and neutral and an opaque base is painted under them; Increase
/// Contrast also adds a key outline and a deeper accent under the white
/// Return label. Bold Text makes the labels heavier.
struct KeyboardKeyTheme: Equatable {
    var dark: Bool
    var highContrast: Bool
    var palette: CandidatePalette
    var bold = false
    var opaque = false
    var liquid = true

    private var glassKeys: Bool { liquid && !opaque }

    /// A solid key colour, moved toward the palette unless `opaque`.
    private func solid(_ light: UInt32, _ dark: UInt32, toward amount: CGFloat) -> UIColor {
        let base = self.dark ? hex(dark) : hex(light)
        if opaque { return base }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        UIColor(palette.color(dark: self.dark)).getRed(&pr, green: &pg, blue: &pb, alpha: &a)
        return UIColor(red: r + (pr - r) * amount, green: g + (pg - g) * amount, blue: b + (pb - b) * amount, alpha: 1)
    }

    // Solid keys only; glass keys take their colour from `glassTint`.
    var characterFill: UIColor { solid(0xFFFFFF, 0x5E5D63, toward: dark ? 0.14 : 0.07) }
    var characterPressed: UIColor { solid(0xDCDBE3, 0x7B7A80, toward: dark ? 0.14 : 0.10) }
    var utilityFill: UIColor { solid(0xCFCED8, 0x3C3B40, toward: dark ? 0.12 : 0.14) }
    var utilityPressed: UIColor { solid(0xFFFFFF, 0x5E5D63, toward: dark ? 0.14 : 0.07) }
    var accentFill: UIColor { UIColor(highContrast ? palette.contrastPill : palette.pill(dark: dark).bottom) }
    var accentPressed: UIColor { UIColor(highContrast ? palette.pill(dark: false).bottom : palette.pill(dark: dark).top) }
    var text: UIColor { dark ? .white : .black }
    var accentText: UIColor { .white }
    var disabledText: UIColor { text.withAlphaComponent(0.32) }
    var shadow: UIColor { .black }
    // A shadow would show through a glass key.
    var shadowOpacity: Float { glassKeys ? 0 : (dark ? 0.55 : 0.22) }
    var outline: UIColor? { highContrast ? (dark ? hex(0xBDBCC4) : hex(0x55545C)) : nil }
    /// Key balloons and the long-press row stay solid over the keys below them.
    var balloonFill: UIColor { dark ? hex(0x6C6C70) : .white }
    var balloonOutline: UIColor { dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.06) }
    var selection: UIColor { accentFill }

    /// The tint of a key's glass, nil for solid keys. As on the system
    /// keyboard, Shift, Delete and the bottom row look like the letters.
    func glassTint(for style: KeyboardKey.Style) -> UIColor? {
        if !glassKeys { return nil }
        if style == .accent { return accentFill }
        let colour = UIColor(palette.color(dark: dark))
        if dark { return colour.withAlphaComponent(0.16) }
        // Light keys are pearl white with a little of the palette in them: the
        // palette's light colour is deep, and on its own it greys the glass.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: 1 - (1 - r) * 0.14, green: 1 - (1 - g) * 0.14, blue: 1 - (1 - b) * 0.14, alpha: 0.7)
    }

    /// What is painted on the key itself: the whole key when solid, only the
    /// pressed shade over the glass otherwise.
    func fill(for style: KeyboardKey.Style, pressed: Bool) -> UIColor {
        if glassKeys {
            if !pressed { return .clear }
            return dark || style == .accent ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 0, alpha: 0.12)
        }
        switch style {
        case .character: return pressed ? characterPressed : characterFill
        case .utility: return pressed ? utilityPressed : utilityFill
        case .accent: return pressed ? accentPressed : accentFill
        }
    }
}

/// Nothing is painted under the keys: the system's own keyboard backdrop shows.
struct KeyboardBackground: View {
    var dark: Bool
    /// The candidate bar, in the keyboard's coordinates.
    var glass: CGRect

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Key feedback is the system click, which follows the user's keyboard
/// sound setting. iOS plays haptics from a keyboard extension only with Full
/// Access, and this keyboard does not ask for it.
enum KeyboardFeedback {
    static func keyDown() {
        UIDevice.current.playInputClick()
    }
}
