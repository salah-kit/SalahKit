import Foundation

/// The owning days a query reads, with their known events and every interval in which an
/// unknown event could occur (RFC 0001, section 4.6).
nonisolated struct ScheduleContext {
  /// A gap with its exact bounds, half-open: `[lower, upper)`.
  struct Window {
    var gap: ScheduleGap
    var lower: Date
    var upper: Date
    /// Whether the gap's kinds include a prayer, which puts it in `W_p` (section 4.7).
    var holdsPrayer: Bool
  }

  /// The known events, in events order: instant, then owning day, then kind.
  let events: [PrayerEvent]
  /// The known prayer events (no sunrise), in events order.
  let prayers: [PrayerEvent]
  /// The missing-event windows and overlap gaps, ordered like coverage gaps.
  let windows: [Window]
  /// The starts of the context days and of the two days after the last one.
  let dayStarts: [Date]

  /// Builds the context of consecutive days.
  ///
  /// - Parameters:
  ///   - days: The context days, consecutive and in order.
  ///   - availability: Each day's checked availability, with iqama applied.
  ///   - starts: The start of each day, then of the two days after the last one.
  ///   - expectedKinds: The source's expected kinds.
  init(
    days: [CivilDay], availability: [PrayerDayAvailability], starts: [Date],
    expectedKinds: Set<PrayerKind>
  ) {
    let known = availability.map { $0.day?.events ?? [] }
    var windows: [Window] = []

    for index in days.indices {
      let missing: [PrayerKind: ScheduleGapReason]
      switch availability[index] {
      case .unavailable(let reason):
        missing = Dictionary(uniqueKeysWithValues: expectedKinds.map { ($0, reason) })
      case .available(_, .complete):
        missing = [:]
      case .available(_, .partial(let kinds)):
        missing = kinds
      }

      var grouped: [WindowKey: Set<PrayerKind>] = [:]
      for (kind, reason) in missing {
        var lower = starts[index]
        var upper = starts[index + 2]
        for event in known[index] {
          if event.kind < kind { lower = max(lower, event.time) }
          if event.kind > kind { upper = min(upper, event.time) }
        }
        if index > 0 {
          for event in known[index - 1] { lower = max(lower, event.time) }
        }
        if index + 1 < days.count {
          for event in known[index + 1] { upper = min(upper, event.time) }
        }
        guard lower < upper else { continue }
        grouped[WindowKey(lower: lower, upper: upper, reason: reason), default: []].insert(kind)
      }
      for (key, kinds) in grouped {
        windows.append(
          Window(
            gap: ScheduleGap(
              interval: DateInterval(start: key.lower, end: key.upper), day: days[index],
              kinds: kinds, reason: key.reason),
            lower: key.lower, upper: key.upper, holdsPrayer: kinds.contains(where: \.isPrayer)))
      }
    }

    // Two available days whose events cross (section 4.3, rule 6) keep their events, and the
    // contradiction becomes an invalid-data gap.
    for index in days.indices.dropLast() {
      guard let last = known[index].map(\.time).max(),
        let first = known[index + 1].map(\.time).min(), last > first
      else { continue }
      let kinds = Set(known[index].filter { $0.time > first }.map(\.kind))
      windows.append(
        Window(
          gap: ScheduleGap(
            interval: DateInterval(start: first, end: last), day: days[index], kinds: kinds,
            reason: .invalidData),
          lower: first, upper: last, holdsPrayer: kinds.contains(where: \.isPrayer)))
    }

    self.windows = windows.sorted(by: Self.precedes)
    self.events = known.joined().sorted {
      ($0.time, $0.scheduleDay, $0.kind) < ($1.time, $1.scheduleDay, $1.kind)
    }
    self.prayers = events.filter(\.kind.isPrayer)
    self.dayStarts = starts
  }

  /// The coverage of `[start, end]`, with `end >= start` (section 4.6).
  func coverage(from start: Date, through end: Date) -> ScheduleCoverage {
    var clipped: [Window] = []
    for window in windows {
      if start == end {
        guard window.lower <= start, start < window.upper else { continue }
      } else {
        guard max(window.lower, start) < min(window.upper, end) else { continue }
      }
      var kept = window
      kept.lower = max(window.lower, start)
      kept.upper = start == end ? start : min(window.upper, end)
      kept.gap.interval = DateInterval(start: kept.lower, end: kept.upper)
      clipped.append(kept)
    }
    clipped.sort(by: Self.precedes)

    var known: [DateInterval] = []
    if start == end {
      if clipped.isEmpty { known.append(DateInterval(start: start, end: end)) }
    } else {
      var cursor = start
      for window in clipped {
        if window.lower > cursor { known.append(DateInterval(start: cursor, end: window.lower)) }
        cursor = max(cursor, window.upper)
      }
      if cursor < end { known.append(DateInterval(start: cursor, end: end)) }
    }
    return ScheduleCoverage(
      requested: DateInterval(start: start, end: end), knownIntervals: known,
      gaps: clipped.map(\.gap))
  }

  /// The state's event fields at `date`, looking ahead through `bound` (section 4.7).
  func snapshot(at date: Date, through bound: Date, policy: StatePolicy) -> Snapshot {
    // Events are in time order: the ones after `date` start at the first later instant.
    let eventsAfter = events.partitioningIndex { $0.time > date }
    let prayersAfter = prayers.partitioningIndex { $0.time > date }
    let previous = events[..<eventsAfter].last.flatMap { event in
      opensBefore(date, after: event.time, prayersOnly: false) ? nil : event
    }
    let latestPrayer = prayers[..<prayersAfter].last.flatMap { event in
      opensBefore(date, after: event.time, prayersOnly: true) ? nil : event
    }
    let next = events[eventsAfter...].first.flatMap { event in
      event.time <= bound && !opensAfter(date, before: event.time, prayersOnly: false)
        ? event : nil
    }
    let nextPrayer = prayers[prayersAfter...].first.flatMap { event in
      event.time <= bound && !opensAfter(date, before: event.time, prayersOnly: true)
        ? event : nil
    }
    let justStarted = latestPrayer.flatMap { event in
      date < Self.justStartedEnd(of: event, policy: policy) ? event : nil
    }
    // The same instant `changeCandidates` uses, so the flag turns on exactly at a candidate.
    let isApproaching = nextPrayer.map { date >= Self.approachingStart(of: $0, policy: policy) }
    return Snapshot(
      previous: previous, latestPrayer: latestPrayer, next: next, nextPrayer: nextPrayer,
      justStarted: justStarted, isApproaching: isApproaching ?? false,
      openGaps: windows.filter { $0.lower <= date && date < $0.upper }.map(\.gap))
  }

  /// The instants at which a state can change, sorted and without repeats: event instants,
  /// gap bounds, approaching thresholds, just-started window ends and the starts of the
  /// context days.
  func changeCandidates(policy: StatePolicy) -> [Date] {
    var candidates = dayStarts
    for event in events {
      candidates.append(event.time)
      if event.kind.isPrayer {
        candidates.append(Self.approachingStart(of: event, policy: policy))
        candidates.append(Self.justStartedEnd(of: event, policy: policy))
      }
    }
    for window in windows {
      candidates.append(window.lower)
      candidates.append(window.upper)
    }
    return Set(candidates).sorted()
  }

  /// Whether a window that has opened by `date` ends after `instant`, so an event at `instant`
  /// can't be asserted as the latest one.
  private func opensBefore(_ date: Date, after instant: Date, prayersOnly: Bool) -> Bool {
    windows.contains { window in
      (!prayersOnly || window.holdsPrayer) && window.lower <= date && window.upper > instant
    }
  }

  /// Whether a window between `date` and `instant` could hold an earlier unknown event.
  private func opensAfter(_ date: Date, before instant: Date, prayersOnly: Bool) -> Bool {
    windows.contains { window in
      (!prayersOnly || window.holdsPrayer) && window.lower < instant && window.upper > date
    }
  }

  static func approachingStart(of event: PrayerEvent, policy: StatePolicy) -> Date {
    event.time.addingTimeInterval(-policy.approaching.nonNegativeSeconds)
  }

  static func justStartedEnd(of event: PrayerEvent, policy: StatePolicy) -> Date {
    switch policy.justStarted {
    case .fixed(let duration):
      event.time.addingTimeInterval(duration.nonNegativeSeconds)
    case .untilIqama(let fallback):
      event.iqama ?? event.time.addingTimeInterval(fallback.nonNegativeSeconds)
    }
  }

  /// Coverage order: start, then owning day, then reason in declaration order.
  private static func precedes(_ lhs: Window, _ rhs: Window) -> Bool {
    (lhs.lower, lhs.gap.day, lhs.gap.reason.order, lhs.upper)
      < (rhs.lower, rhs.gap.day, rhs.gap.reason.order, rhs.upper)
  }

  private struct WindowKey: Hashable {
    var lower: Date
    var upper: Date
    var reason: ScheduleGapReason
  }
}

/// A state's semantic content at one instant: its event fields, whether it's approaching and
/// the gaps that contain the instant (RFC 0001, section 4.7).
nonisolated struct Snapshot {
  var previous: PrayerEvent?
  var latestPrayer: PrayerEvent?
  var next: PrayerEvent?
  var nextPrayer: PrayerEvent?
  var justStarted: PrayerEvent?
  var isApproaching: Bool
  var openGaps: [ScheduleGap]

  var isAvailable: Bool {
    previous != nil || latestPrayer != nil || next != nil || nextPrayer != nil
  }

  /// Whether two snapshots describe the same state: the same events by identity, the same
  /// approaching flag and the same open gaps.
  func isSameState(as other: Snapshot) -> Bool {
    previous?.id == other.previous?.id && latestPrayer?.id == other.latestPrayer?.id
      && next?.id == other.next?.id && nextPrayer?.id == other.nextPrayer?.id
      && justStarted?.id == other.justStarted?.id && isApproaching == other.isApproaching
      && Set(openGaps) == Set(other.openGaps)
  }
}

nonisolated extension RandomAccessCollection {
  /// The index of the first element for which `isAfter` is true, in a collection where every
  /// such element follows every other one; `endIndex` when there's none. A binary search.
  func partitioningIndex(where isAfter: (Element) -> Bool) -> Index {
    var low = startIndex
    var count = self.count
    while count > 0 {
      let half = count / 2
      let middle = index(low, offsetBy: half)
      if isAfter(self[middle]) {
        count = half
      } else {
        low = index(after: middle)
        count -= half + 1
      }
    }
    return low
  }
}
