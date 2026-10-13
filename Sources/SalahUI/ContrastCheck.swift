import Foundation

/// Checks a theme color against the surface it's drawn on and the colors an app reserves.
///
/// The defaults are the guardrails of Salah's widget theme editor: a contrast of at least 3:1,
/// WCAG's floor for large text such as a countdown, and a distance of at least 0.28 from each
/// reserved color, so that a custom accent never looks like the red or green an app uses for
/// alerts.
///
/// ```swift
/// let check = ContrastCheck()
/// let problems = check.problems(foreground: accent, background: surface,
///                               reserved: [alertRed, countUpGreen])
/// if problems.isEmpty { /* the accent passes */ }
/// ```
///
/// Body text needs more than the large-text floor: use `ContrastCheck(minimumContrast: 4.5)`
/// for it. ``ThemeColor/adjustedForContrast(against:ratio:)`` suggests a fix for a color that
/// fails.
nonisolated public struct ContrastCheck: Hashable, Sendable {
  /// A way a color fails the check.
  public enum Problem: Hashable, Sendable {
    /// The contrast against the background is below ``ContrastCheck/minimumContrast``; the
    /// value is the measured ratio.
    case lowContrast(Double)
    /// The color is closer than ``ContrastCheck/minimumReservedDistance`` to this reserved
    /// color.
    case tooCloseToReserved(ThemeColor)
  }

  /// The lowest contrast ratio the foreground may have against the background. The default,
  /// 3, is WCAG's floor for large text.
  public var minimumContrast: Double

  /// The smallest ``ThemeColor/distance(to:)`` the foreground may have from each reserved
  /// color. The default is 0.28.
  public var minimumReservedDistance: Double

  /// Creates a check.
  ///
  /// - Parameters:
  ///   - minimumContrast: The lowest contrast ratio against the background.
  ///   - minimumReservedDistance: The smallest distance from each reserved color.
  public init(minimumContrast: Double = 3, minimumReservedDistance: Double = 0.28) {
    self.minimumContrast = minimumContrast
    self.minimumReservedDistance = minimumReservedDistance
  }

  /// The ways `foreground` fails the check: low contrast first, then each reserved color it's
  /// too close to, in the order given. Empty when it passes.
  ///
  /// - Parameters:
  ///   - foreground: The color to check, such as a theme's accent.
  ///   - background: The surface it's drawn on.
  ///   - reserved: Colors it must stay clear of, such as an app's alert colors.
  public func problems(
    foreground: ThemeColor, background: ThemeColor, reserved: [ThemeColor] = []
  ) -> [Problem] {
    var problems: [Problem] = []
    let ratio = ThemeColor.contrastRatio(foreground, background)
    if ratio < minimumContrast {
      problems.append(.lowContrast(ratio))
    }
    for color in reserved where foreground.distance(to: color) < minimumReservedDistance {
      problems.append(.tooCloseToReserved(color))
    }
    return problems
  }
}
