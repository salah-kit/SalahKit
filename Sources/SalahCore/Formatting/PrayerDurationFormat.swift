import Foundation

/// Countdown and elapsed-time text, such as `45s`, `12m` and `2:15`, built on Foundation's
/// `Duration` formatting.
///
/// Every width rounds down, so the screen never shows a minute that hasn't passed: 8,130
/// seconds (2 h 15 m 30 s) reads `2:15` and "2 hours, 15 minutes". Negative and non-finite
/// values count as zero.
///
/// Digits follow the locale. A bare identifier can lose its numbering system, so pass a locale
/// from ``PrayerLocale/resolved(_:)-(String)`` when the language uses native digits.
///
/// ```swift
/// let locale = PrayerLocale.resolved("ar")
/// PrayerDurationFormat.string(720, locale: locale)                        // "١٢د"
/// PrayerDurationFormat.string(45, direction: .elapsed, locale: locale)    // "+٤٥ث"
/// PrayerDurationFormat.string(8_130, width: .spoken, locale: .init(identifier: "en"))
/// // "2 hours, 15 minutes"
/// ```
nonisolated public enum PrayerDurationFormat {
  /// Whether the duration counts down to an event or up from one.
  public enum Direction: Sendable {
    /// Time left until an event. Compact text has no sign.
    case remaining
    /// Time since an event. Compact text carries a leading `+`.
    case elapsed
  }

  /// How much text the duration takes.
  public enum Width: Sendable {
    /// Short text for a timer: narrow seconds under a minute (`45s`), narrow minutes under an
    /// hour (`12m`), then hours and minutes with the locale's time separator (`2:15`).
    case compact
    /// Full words for VoiceOver: wide seconds under a minute (`45 seconds`), otherwise wide hours
    /// and minutes (`2 hours, 15 minutes`). Spoken text never carries a sign; the surrounding
    /// sentence says "remaining" or "ago".
    case spoken
  }

  /// The largest number of seconds formatted; longer durations are shown as this many.
  static let maximumSeconds: Int64 = 1_000_000_000_000_000

  /// Formats a duration.
  ///
  /// - Parameters:
  ///   - seconds: The duration. It's rounded down to whole seconds; negative and non-finite
  ///     values count as zero.
  ///   - direction: Whether the time is remaining or elapsed. Only compact text shows it.
  ///   - width: Compact timer text or spoken text.
  ///   - locale: The locale for digits, units and the time separator.
  ///   - bidiIsolated: Whether to wrap the text in U+2068 FIRST STRONG ISOLATE and U+2069 POP
  ///     DIRECTIONAL ISOLATE, so it keeps its order inside text of the opposite direction.
  /// - Returns: The formatted duration.
  public static func string(
    _ seconds: TimeInterval, direction: Direction = .remaining, width: Width = .compact,
    locale: Locale, bidiIsolated: Bool = false
  ) -> String {
    let value = wholeSeconds(seconds)
    let text: String
    switch width {
    case .compact:
      let core = compact(value, locale: locale)
      text = direction == .elapsed ? "+\(core)" : core
    case .spoken:
      text = spoken(value, locale: locale)
    }
    return bidiIsolated ? "\u{2068}\(text)\u{2069}" : text
  }

  /// `max(0, floor(seconds))`, with non-finite input as zero and a cap at ``maximumSeconds``.
  static func wholeSeconds(_ seconds: TimeInterval) -> Int64 {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return Int64(min(seconds.rounded(.down), Double(maximumSeconds)))
  }

  private static func compact(_ value: Int64, locale: Locale) -> String {
    let isPersian = locale.language.languageCode?.identifier == "fa"
    switch value {
    case ..<60:
      if isPersian {
        return persian(value, unit: "ث", locale: locale)
      }
      return Duration.seconds(value)
        .formatted(.units(allowed: [.seconds], width: .narrow).locale(locale))
    case ..<3_600:
      if isPersian {
        return persian(value / 60, unit: "د", locale: locale)
      }
      return Duration.seconds(value / 60 * 60)
        .formatted(.units(allowed: [.minutes], width: .narrow).locale(locale))
    default:
      return Duration.seconds(value / 60 * 60)
        .formatted(
          .time(pattern: .hourMinute(padHourToLength: 1, roundSeconds: .down)).locale(locale))
    }
  }

  private static func spoken(_ value: Int64, locale: Locale) -> String {
    if value < 60 {
      return Duration.seconds(value)
        .formatted(.units(allowed: [.seconds], width: .wide).locale(locale))
    }
    return Duration.seconds(value / 60 * 60)
      .formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale))
  }

  /// Persian compact text: Foundation's narrow units fall back to Latin letters (`۴۵s`), so
  /// these tiers use Salah's abbreviations after the locale's digits (`۴۵ث`, `۱۲د`).
  private static func persian(_ number: Int64, unit: String, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.usesGroupingSeparator = false
    let digits = formatter.string(from: NSNumber(value: number)) ?? String(number)
    return "\(digits)\(unit)"
  }
}
