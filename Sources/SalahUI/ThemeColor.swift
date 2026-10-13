import Foundation

/// An sRGB color as plain components, for checking and adjusting a theme's colors.
///
/// The math is Salah's, from its widget theme editor: WCAG relative luminance and contrast
/// ratio, a "fix contrast" adjustment that keeps the hue, and a distance for keeping a theme's
/// colors away from the colors an app reserves for alerts. ``ContrastCheck`` puts them together
/// with Salah's thresholds.
///
/// ```swift
/// let accent = ThemeColor(red: 0.04, green: 0.52, blue: 1.00)
/// let surface = ThemeColor(red: 0.075, green: 0.094, blue: 0.180)
/// ThemeColor.contrastRatio(accent, surface)   // about 5.0
/// ```
///
/// Components are between 0 and 1. In every calculation, a value outside that range counts as
/// the nearest end of it, and a value that isn't a number counts as 0. Opacity is carried but
/// not used: the
/// math treats colors as opaque, so check a translucent color's result against what it's drawn
/// over. In SwiftUI, ``color`` gives the color to draw.
nonisolated public struct ThemeColor: Codable, Hashable, Sendable {
  /// The red component, from 0 to 1.
  public var red: Double
  /// The green component, from 0 to 1.
  public var green: Double
  /// The blue component, from 0 to 1.
  public var blue: Double
  /// The opacity, from 0 to 1. The contrast math ignores it.
  public var opacity: Double

  /// Creates a color from sRGB components.
  public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  /// The WCAG 2 relative luminance, from 0 for black to 1 for white.
  public var relativeLuminance: Double {
    func linear(_ component: Double) -> Double {
      let value = Self.unit(component)
      return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// The WCAG 2 contrast ratio between two colors, from 1 (none) to 21 (black on white).
  ///
  /// WCAG asks for at least 4.5 for body text and 3 for large text.
  public static func contrastRatio(_ first: ThemeColor, _ second: ThemeColor) -> Double {
    let a = first.relativeLuminance
    let b = second.relativeLuminance
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  /// This color, moved toward white on a dark surface or toward black on a light one until it
  /// reaches `ratio` against `surface`.
  ///
  /// The color moves in twenty equal steps, keeping its hue; the first step that reaches the
  /// ratio wins. A color that already reaches it comes back unchanged. One that can't, because
  /// the ratio is out of reach on this surface, ends at white or black. A surface counts as
  /// dark when its relative luminance is below 0.5. Opacity is kept.
  ///
  /// - Parameters:
  ///   - surface: The color it's drawn on.
  ///   - ratio: The contrast to reach. The default, 4.5, is WCAG's for body text.
  /// - Returns: The adjusted color.
  public func adjustedForContrast(against surface: ThemeColor, ratio: Double = 4.5) -> ThemeColor {
    if Self.contrastRatio(self, surface) >= ratio { return self }
    let towardWhite = surface.relativeLuminance < 0.5
    let start = (Self.unit(red), Self.unit(green), Self.unit(blue))
    func moved(_ component: Double, by fraction: Double) -> Double {
      component + ((towardWhite ? 1 : 0) - component) * fraction
    }
    var candidate = self
    for step in 1...20 {
      let fraction = Double(step) / 20
      candidate = ThemeColor(
        red: moved(start.0, by: fraction), green: moved(start.1, by: fraction),
        blue: moved(start.2, by: fraction), opacity: opacity)
      if Self.contrastRatio(candidate, surface) >= ratio { break }
    }
    return candidate
  }

  /// The straight-line distance between two colors' sRGB components, from 0 for the same color
  /// to about 1.73 for black and white.
  ///
  /// It's a rough measure of how alike two colors look. ``ContrastCheck`` uses it to keep a
  /// theme's colors away from reserved ones, such as an alert's red.
  public func distance(to other: ThemeColor) -> Double {
    let dr = Self.unit(red) - Self.unit(other.red)
    let dg = Self.unit(green) - Self.unit(other.green)
    let db = Self.unit(blue) - Self.unit(other.blue)
    return (dr * dr + dg * dg + db * db).squareRoot()
  }

  /// A component within 0 to 1; a value that isn't a number counts as 0.
  static func unit(_ component: Double) -> Double {
    component.isNaN ? 0 : min(max(component, 0), 1)
  }
}
