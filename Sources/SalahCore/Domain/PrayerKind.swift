import Foundation

/// The six daily events of a prayer schedule, in canonical order.
///
/// Sunrise isn't a prayer: it ends Fajr's time. Use ``isPrayer`` when only prayers matter,
/// for example when choosing the next prayer to count down to.
///
/// `PrayerKind` is `Comparable` in canonical order (fajr first, isha last), and a dictionary
/// keyed by it encodes as a JSON object keyed by the raw values (`"fajr"`, `"isha"`).
nonisolated public enum PrayerKind: String, Codable, Hashable, CodingKeyRepresentable,
  CaseIterable, Comparable, Sendable
{
  /// The dawn prayer.
  case fajr
  /// Sunrise, which ends Fajr's time. It isn't a prayer.
  case sunrise
  /// The midday prayer. On Friday it can be observed as Jumu'ah, when a source declares it.
  case dhuhr
  /// The afternoon prayer.
  case asr
  /// The sunset prayer.
  case maghrib
  /// The night prayer.
  case isha

  /// Whether this kind is a prayer. Sunrise ends Fajr's time; it isn't a prayer.
  public var isPrayer: Bool { self != .sunrise }

  /// The position in canonical order, from 0 for fajr to 5 for isha.
  var order: Int {
    switch self {
    case .fajr: 0
    case .sunrise: 1
    case .dhuhr: 2
    case .asr: 3
    case .maghrib: 4
    case .isha: 5
    }
  }

  /// Compares kinds in canonical order: fajr, sunrise, dhuhr, asr, maghrib, isha.
  public static func < (lhs: PrayerKind, rhs: PrayerKind) -> Bool {
    lhs.order < rhs.order
  }
}
