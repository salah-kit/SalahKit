import Foundation

/// A local clock time on an owning day, as a timetable prints it.
///
/// `dayOffset` places the clock time on the civil day after the owning day: that's how a
/// timetable writes Monday's Isha at 00:15 on Tuesday (`"00:15+1"`). Valid values are an hour
/// from 0 to 23, a minute from 0 to 59 and a day offset of 0 or 1; sources treat anything else
/// as invalid data.
///
/// A wall time encodes as `"HH:MM"`, with a `"+1"` suffix for the next civil day. Parsing
/// checks the shape only and accepts a one-digit hour (`"5:05"`).
nonisolated public struct WallClockTime: Codable, Hashable, Sendable, LosslessStringConvertible {
  /// The hour, from 0 to 23.
  public var hour: Int
  /// The minute, from 0 to 59.
  public var minute: Int
  /// 0 for the owning day, 1 for the civil day after it.
  public var dayOffset: Int

  /// Creates a wall time.
  public init(hour: Int, minute: Int, dayOffset: Int = 0) {
    self.hour = hour
    self.minute = minute
    self.dayOffset = dayOffset
  }

  /// Parses `"HH:MM"` or `"HH:MM+N"`. Returns `nil` for any other shape.
  public init?(_ description: String) {
    var text = Substring(description)
    var dayOffset = 0
    if let plus = text.firstIndex(of: "+") {
      let offsetText = text[text.index(after: plus)...]
      guard !offsetText.isEmpty, offsetText.allSatisfy({ $0.isASCII && $0.isNumber }),
        let parsed = Int(offsetText)
      else { return nil }
      dayOffset = parsed
      text = text[..<plus]
    }
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
      parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
      let hour = Int(parts[0]), let minute = Int(parts[1])
    else { return nil }
    self.init(hour: hour, minute: minute, dayOffset: dayOffset)
  }

  /// The time as `"HH:MM"`, with `"+N"` when the day offset isn't zero.
  public var description: String {
    let clock = "\(InstantText.pad(hour, 2)):\(InstantText.pad(minute, 2))"
    return dayOffset == 0 ? clock : "\(clock)+\(dayOffset)"
  }

  /// Whether the hour, minute and day offset are within the supported ranges.
  public var isValid: Bool {
    (0...23).contains(hour) && (0...59).contains(minute) && (0...1).contains(dayOffset)
  }

  /// Decodes `"HH:MM"` or `"HH:MM+1"`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let time = WallClockTime(text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a time as HH:MM or HH:MM+1, found \"\(text)\".")
    }
    self = time
  }

  /// Encodes `"HH:MM"`, or `"HH:MM+1"` for the next civil day.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

/// A published time: a local wall time to resolve in the location's zone, or an instant the
/// publisher already resolved.
///
/// Encodes as a wall-time string (`"21:15"`, `"00:15+1"`) or as an ISO 8601 instant with an
/// offset (`"2026-06-21T23:15:00Z"`, `"2026-06-22T00:15:00+01:00"`).
nonisolated public enum TimetableTime: Codable, Hashable, Sendable {
  /// A local clock time on the owning day (or the next one), resolved in the location's zone.
  case local(WallClockTime)
  /// An instant already resolved by the publisher. It's kept as is, never reinterpreted.
  case instant(Date)

  /// Decodes a wall-time string or an ISO 8601 instant.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    if text.contains("T") || text.contains("t") {
      guard let date = InstantText.parse(text) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected an ISO 8601 instant with an offset, found \"\(text)\".")
      }
      self = .instant(date)
    } else {
      guard let time = WallClockTime(text) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected HH:MM, HH:MM+1 or an instant, found \"\(text)\".")
      }
      self = .local(time)
    }
  }

  /// Encodes a wall-time string or a UTC ISO 8601 instant.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .local(let time): try container.encode(time.description)
    case .instant(let date): try container.encode(InstantText.format(date))
    }
  }
}

/// How to read a local time that a clock change makes repeated or nonexistent.
///
/// The default rejects both, so an ambiguous published time becomes missing data with reason
/// ``ScheduleGapReason/unresolvedWallTime`` instead of a guess. A publisher or app can choose
/// otherwise explicitly.
nonisolated public struct WallTimeResolution: Codable, Hashable, Sendable {
  /// What to do with a local time that occurs twice, when clocks fall back.
  public enum RepeatedTime: String, Codable, Hashable, Sendable {
    /// Leave the time unresolved.
    case reject
    /// Use the first occurrence.
    case earlier
    /// Use the second occurrence.
    case later
  }

  /// What to do with a local time that doesn't occur, when clocks spring forward.
  public enum NonexistentTime: String, Codable, Hashable, Sendable {
    /// Leave the time unresolved.
    case reject
    /// Use the instant the skipped range ends: in a 02:00 to 03:00 gap, 02:30 becomes 03:00.
    case nextValid
  }

  /// The rule for repeated local times.
  public var repeated: RepeatedTime
  /// The rule for nonexistent local times.
  public var nonexistent: NonexistentTime

  /// Creates a resolution policy. The defaults reject both cases.
  public init(repeated: RepeatedTime = .reject, nonexistent: NonexistentTime = .reject) {
    self.repeated = repeated
    self.nonexistent = nonexistent
  }

  private enum CodingKeys: String, CodingKey {
    case repeated, nonexistent
  }

  /// Decodes a policy; a missing field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      repeated: try container.decodeIfPresent(RepeatedTime.self, forKey: .repeated) ?? .reject,
      nonexistent: try container.decodeIfPresent(NonexistentTime.self, forKey: .nonexistent)
        ?? .reject)
  }
}
