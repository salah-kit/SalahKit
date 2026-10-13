import Foundation

/// Resolves local wall-clock times in a time zone into instants (RFC 0001, section 4.2).
///
/// Works in whole seconds since 1970. A local date-time is written as the seconds a UTC clock
/// would show at the same date and time, so the instant `t` has the local time
/// `t + offset(t)`.
nonisolated enum WallTimeResolver {
  /// The instant of a wall time on an owning day, or `nil` when the policy rejects it.
  static func instant(
    of time: WallClockTime, on day: CivilDay, in zone: TimeZone, policy: WallTimeResolution
  ) -> Date? {
    let days: Int = day.daysSinceEpoch + time.dayOffset
    let seconds: Int = time.hour * 3_600 + time.minute * 60
    let resolved = resolve(
      local: days * 86_400 + seconds, in: zone, repeated: policy.repeated,
      nonexistent: policy.nonexistent)
    return resolved.map { Date(timeIntervalSince1970: TimeInterval($0)) }
  }

  /// The first instant of a day: local midnight, read as the earlier instant when it repeats
  /// and as the next valid instant when it doesn't exist.
  static func startSeconds(of day: CivilDay, in zone: TimeZone) -> Int {
    let midnight = day.daysSinceEpoch * 86_400
    return instants(atLocal: midnight, in: zone).first
      ?? endOfSkippedRange(containing: midnight, in: zone)
  }

  /// Resolves a local date-time with a policy for repeated and nonexistent times.
  static func resolve(
    local: Int, in zone: TimeZone, repeated: WallTimeResolution.RepeatedTime,
    nonexistent: WallTimeResolution.NonexistentTime
  ) -> Int? {
    let candidates = instants(atLocal: local, in: zone)
    switch candidates.count {
    case 0:
      return nonexistent == .nextValid ? endOfSkippedRange(containing: local, in: zone) : nil
    case 1:
      return candidates.first
    default:
      switch repeated {
      case .reject: return nil
      case .earlier: return candidates.first
      case .later: return candidates.last
      }
    }
  }

  /// Every instant whose local time in `zone` is exactly `local`, earliest first.
  ///
  /// The candidates are `local - o` for each offset `o` in effect within a day of `local`; a
  /// candidate counts only when the zone's offset at it is `o`. Offsets are sampled a day
  /// before, at and a day after `local`, then at each candidate, which finds every candidate
  /// around one offset change, whatever its size.
  static func instants(atLocal local: Int, in zone: TimeZone) -> [Int] {
    var offsets = Set([local - 86_400, local, local + 86_400].map { offset(at: $0, in: zone) })
    for value in Array(offsets) {
      offsets.insert(offset(at: local - value, in: zone))
    }
    return Set(offsets.map { local - $0 }).filter { offset(at: $0, in: zone) == local - $0 }
      .sorted()
  }

  /// The instant at which the skipped range that contains `local` ends: the first instant
  /// whose local time is later than `local`.
  static func endOfSkippedRange(containing local: Int, in zone: TimeZone) -> Int {
    // Offsets stay within a day, so the local time a day before `local` is earlier than it and
    // the local time a day after is later.
    var earlier = local - 86_400
    var later = local + 86_400
    while later - earlier > 1 {
      let middle = earlier + (later - earlier) / 2
      if middle + offset(at: middle, in: zone) > local {
        later = middle
      } else {
        earlier = middle
      }
    }
    return later
  }

  static func offset(at seconds: Int, in zone: TimeZone) -> Int {
    zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds)))
  }
}
