import Foundation

/// How a refresh plan chooses its dates.
nonisolated public enum RefreshStrategy: Hashable, Sendable {
  /// An entry wherever the known state or its coverage changes. Pair it with a view that counts
  /// down by itself, such as `Text(timerInterval:)`.
  case stateChanges
  /// Also an entry every `fine` near each prayer (within `window` of it) and every `coarse`
  /// elsewhere, for views that draw static text.
  case steps(fine: Duration, coarse: Duration, window: Duration)
}

/// The dates at which a widget needs a new entry, each with its state.
///
/// SalahCore has no WidgetKit; SalahWidgets turns a plan into a timeline. The dates say when the
/// content changes. WidgetKit still decides when it shows them.
nonisolated public struct RefreshPlan: Hashable, Sendable {
  /// One planned entry.
  public struct Entry: Hashable, Sendable {
    /// When the entry takes effect.
    public var date: Date
    /// The state from `date` until the next entry. It looks ahead past the horizon, so an entry
    /// near the horizon's end still knows a prayer just after it.
    public var state: ScheduleState
  }

  /// The requested interval, after the query limit of ``PrayerSchedule/maximumQueryDays``.
  public var horizon: DateInterval
  /// The entries in date order. The first is at `horizon.start`.
  public var entries: [Entry]
  /// The end of the plan's validity: `horizon.end`, or an earlier cutoff when the entry budget
  /// couldn't hold every change. SalahWidgets places its timeline-expired entry here.
  public var validUntil: Date

  /// The entries' dates, in order.
  public var dates: [Date] { entries.map(\.date) }

  /// Whether the entry budget ended the plan before the horizon's end.
  public var isTruncated: Bool { validUntil < horizon.end }
}

/// Why a refresh plan can't be made.
nonisolated public enum RefreshPlanError: Error, Hashable, Sendable {
  /// The horizon's end isn't after its start.
  case nonPositiveHorizon
  /// The limit is below 2, leaving no room for an initial entry and the cutoff.
  case limitTooSmall
  /// A `steps` strategy has a step that isn't positive, or a negative window.
  case invalidStrategy
}

nonisolated extension PrayerSchedule {
  /// Plans the dates in `[start, end)` at which a widget needs a new entry, with the state for
  /// each.
  ///
  /// The dates are `start` and every instant where the known state or coverage changes, plus
  /// the `steps` grid when you choose it. Every entry's state looks ahead to the start of the
  /// second civil day after `end`'s, so an entry near the end of the horizon still knows the
  /// next prayer. When the dates don't fit in `limit` entries, the plan keeps the first
  /// `limit - 1` and sets ``RefreshPlan/validUntil`` to the next date, instead of skipping a
  /// change and claiming to cover it.
  ///
  /// - Parameters:
  ///   - start: The first entry's date.
  ///   - end: The end of the horizon; beyond ``maximumQueryDays`` it's clamped.
  ///   - strategy: How to choose the dates.
  ///   - policy: When a prayer counts as approaching or just started.
  ///   - limit: The most entries the plan may use, counting one for its cutoff.
  /// - Throws: ``RefreshPlanError`` for an empty horizon, a limit below 2 or an invalid
  ///   strategy, checked in that order.
  public func refreshPlan(
    from start: Date, through end: Date, strategy: RefreshStrategy = .stateChanges,
    policy: StatePolicy = StatePolicy(), limit: Int = 96
  ) throws(RefreshPlanError) -> RefreshPlan {
    let start = Gregorian.clamped(start)
    guard Gregorian.clamped(end) > start else { throw .nonPositiveHorizon }
    guard limit >= 2 else { throw .limitTooSmall }
    if case .steps(let fine, let coarse, let window) = strategy,
      fine <= .zero || coarse <= .zero || window < .zero
    {
      throw .invalidStrategy
    }

    let engine = ScheduleEngine(schedule: self)
    let horizon = DateInterval(
      start: start, end: engine.clampedEnd(from: start, through: Gregorian.clamped(end)))
    let end = horizon.end
    let bound = engine.start(of: engine.civilDay(containing: end).adding(days: 2))
    var states: [Date: ScheduleState] = [:]
    func state(at date: Date) -> ScheduleState {
      if let state = states[date] { return state }
      // The same state `state(at:through:policy:)` gives, including its query limit.
      let state = engine.state(
        at: date, through: engine.clampedEnd(from: date, through: bound), policy: policy)
      states[date] = state
      return state
    }

    // Only the first `limit` dates matter, so each source of dates stops once it can't add
    // one before the current cutoff.
    var dates = [start]
    func add(_ candidates: [Date]) {
      dates = Array(Set(dates + candidates).sorted().prefix(limit))
    }
    func cutoff() -> Date { dates.count >= limit ? dates[limit - 1] : end }

    var transitions: [Date] = []
    var instant = start
    while transitions.count < limit, let next = state(at: instant).changesAt, next < end,
      next > instant
    {
      transitions.append(next)
      instant = next
    }
    add(transitions)

    if case .steps(let fine, let coarse, let window) = strategy {
      add(
        Self.stepDates(
          prayers: events(
            from: start.addingTimeInterval(-window.nonNegativeSeconds),
            through: end.addingTimeInterval(window.nonNegativeSeconds)
          ).events.filter(\.kind.isPrayer).map(\.time),
          start: start, end: end, fine: fine.seconds, coarse: coarse.seconds,
          window: window.seconds, limit: limit, cutoff: cutoff()))
    }

    let fits = dates.count + 1 <= limit
    let kept = fits ? dates : Array(dates.prefix(limit - 1))
    return RefreshPlan(
      horizon: horizon,
      entries: kept.map { RefreshPlan.Entry(date: $0, state: state(at: $0)) },
      validUntil: fits ? end : dates[limit - 1])
  }

  /// The `steps` grid in `(start, end)`: every `fine` within `window` of a prayer, and every
  /// `coarse` from `start` except within `window` of a prayer.
  ///
  /// Only the plan's first `limit` dates matter, so the grid stops at `cutoff` and keeps no
  /// more than its own `limit` smallest dates.
  static func stepDates(
    prayers: [Date], start: Date, end: Date, fine: TimeInterval, coarse: TimeInterval,
    window: TimeInterval, limit: Int, cutoff: Date
  ) -> [Date] {
    var last = min(end, cutoff)
    var dates: [Date] = []
    func trim() {
      dates = Array(Set(dates).sorted().prefix(limit))
      if dates.count == limit, let largest = dates.last { last = min(last, largest) }
    }

    let reach = (window / fine).rounded(.down)
    for prayer in prayers.sorted() {
      guard prayer.addingTimeInterval(-window) < last else { break }
      var step = max(-reach, (start.timeIntervalSince(prayer) / fine).rounded(.down))
      var produced = 0
      while step <= reach, produced < limit {
        let date = prayer.addingTimeInterval(step * fine)
        if date >= last { break }
        if date > start {
          dates.append(date)
          produced += 1
        }
        step += 1
      }
      if dates.count >= 2 * limit { trim() }
    }

    var step = 1.0
    var produced = 0
    while produced < limit {
      let date = start.addingTimeInterval(step * coarse)
      guard date < last else { break }
      if !prayers.contains(where: { abs(date.timeIntervalSince($0)) <= window }) {
        dates.append(date)
        produced += 1
      }
      step += 1
    }
    trim()
    return dates
  }
}
