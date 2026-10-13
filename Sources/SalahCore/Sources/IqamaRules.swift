import Foundation

/// A mosque's own rules for congregation (iqama) times, applied where the source provides
/// none.
///
/// A source's published iqama always wins over a rule. A declared Jumu'ah uses only
/// ``jumuah``: its congregation follows the khutbah, so the Dhuhr rule never applies to it.
/// Rules for sunrise are ignored. A rule that gives a time before its prayer, or two or more
/// days after the owning day starts, gives no iqama.
///
/// Encodes as `{"rules": {"fajr": {"after": 20}, "isha": {"at": "20:30"}}, "jumuah": {"at":
/// "13:30"}}`, with an optional `wallTimeResolution`.
nonisolated public struct IqamaRules: Codable, Hashable, Sendable {
  /// One prayer's iqama rule.
  ///
  /// Encodes as `{"after": 10}` or `{"at": "21:00"}`.
  public enum Rule: Codable, Hashable, Sendable {
    /// A number of minutes after the prayer's time, counted in elapsed time, so a clock change
    /// doesn't affect it. A negative number gives no iqama.
    case after(minutes: Int)
    /// A local time on the prayer's owning day, resolved in the location's zone.
    case at(WallClockTime)

    private enum CodingKeys: String, CodingKey {
      case after, at
    }

    /// Decodes `{"after": minutes}` or `{"at": "HH:MM"}`.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let minutes = try container.decodeIfPresent(Int.self, forKey: .after) {
        self = .after(minutes: minutes)
      } else if let time = try container.decodeIfPresent(WallClockTime.self, forKey: .at) {
        self = .at(time)
      } else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription:
              "Expected an iqama rule as {\"after\": minutes} or {\"at\": \"HH:MM\"}."))
      }
    }

    /// Encodes `{"after": minutes}` or `{"at": "HH:MM"}`.
    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .after(let minutes): try container.encode(minutes, forKey: .after)
      case .at(let time): try container.encode(time, forKey: .at)
      }
    }
  }

  /// Rules for ordinary prayers, by kind.
  public var rules: [PrayerKind: Rule]
  /// The rule for a declared Jumu'ah, if the mosque has one.
  public var jumuah: Rule?
  /// How to read ``Rule/at(_:)`` times that a clock change makes repeated or nonexistent.
  public var wallTimeResolution: WallTimeResolution

  /// Creates iqama rules.
  public init(
    rules: [PrayerKind: Rule] = [:], jumuah: Rule? = nil,
    wallTimeResolution: WallTimeResolution = WallTimeResolution()
  ) {
    self.rules = rules
    self.jumuah = jumuah
    self.wallTimeResolution = wallTimeResolution
  }

  private enum CodingKeys: String, CodingKey {
    case rules, jumuah, wallTimeResolution
  }

  /// Decodes rules; every field is optional.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rules: try container.decodeIfPresent([PrayerKind: Rule].self, forKey: .rules) ?? [:],
      jumuah: try container.decodeIfPresent(Rule.self, forKey: .jumuah),
      wallTimeResolution: try container.decodeIfPresent(
        WallTimeResolution.self, forKey: .wallTimeResolution) ?? WallTimeResolution())
  }
}
