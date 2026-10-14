import SalahUI
import SwiftUI

/// The Home Screen widget's colors, light and dark, as `ThemeColor`s so a unit test can check
/// them with SalahUI's `ContrastCheck`.
///
/// Lock Screen widgets don't use them: the system draws accessory widgets in its own tint.
nonisolated struct WidgetPalette: Hashable, Sendable {
  /// The widget's background.
  var surface: ThemeColor
  /// Names, times and headlines.
  var ink: ThemeColor
  /// Passed prayers and explanations.
  var secondaryInk: ThemeColor
  /// The next prayer and its countdown.
  var accent: ThemeColor
  /// The symbol of a problem: unavailable or expired times.
  var notice: ThemeColor

  static let light = WidgetPalette(
    surface: ThemeColor(red: 0.973, green: 0.965, blue: 0.937),
    ink: ThemeColor(red: 0.110, green: 0.118, blue: 0.141),
    secondaryInk: ThemeColor(red: 0.330, green: 0.345, blue: 0.380),
    accent: ThemeColor(red: 0.000, green: 0.400, blue: 0.380),
    notice: ThemeColor(red: 0.620, green: 0.330, blue: 0.000))

  static let dark = WidgetPalette(
    surface: ThemeColor(red: 0.071, green: 0.090, blue: 0.118),
    ink: ThemeColor(red: 0.937, green: 0.937, blue: 0.918),
    secondaryInk: ThemeColor(red: 0.660, green: 0.680, blue: 0.710),
    accent: ThemeColor(red: 0.380, green: 0.820, blue: 0.760),
    notice: ThemeColor(red: 0.980, green: 0.720, blue: 0.300))

  /// The colors the accent must never be mistaken for: the system's red, which iOS uses for
  /// alerts, in light and dark mode.
  static let reserved: [ThemeColor] = [
    ThemeColor(red: 1.000, green: 0.231, blue: 0.188),
    ThemeColor(red: 1.000, green: 0.271, blue: 0.227),
  ]

  /// The palette for a color scheme.
  static func of(_ scheme: ColorScheme) -> WidgetPalette {
    scheme == .dark ? dark : light
  }
}
