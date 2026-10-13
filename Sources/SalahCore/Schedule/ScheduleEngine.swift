import Foundation

/// Answers one public query, reading each owning day from the source at most once.
///
/// A state at an instant uses its own context: the days from two before the instant's civil
/// day through the bound's civil day. Evaluating `changesAt` and refresh plans moves that
/// context, so the engine keeps the days and day starts it has read, and the few contexts it
/// built last with their change candidates. Those queries move forward in time, so older
/// contexts aren't needed again, and a long plan doesn't hold a context for every day.
nonisolated final class ScheduleEngine {
  let schedule: PrayerSchedule
  private let zone: TimeZone
  private let expectedKinds: Set<PrayerKind>
  private var days: [CivilDay: PrayerDayAvailability] = [:]
  private var starts: [CivilDay: Date] = [:]
  private var contexts: [ContextKey: CachedContext] = [:]
  private var contextOrder: [ContextKey] = []
  private static let contextCacheLimit = 8

  init(schedule: PrayerSchedule) {
    self.schedule = schedule
    self.zone = schedule.location.timeZone
    self.expectedKinds = schedule.source.expectedKinds
  }

  /// The civil day that contains `date` in the location's zone.
  func civilDay(containing date: Date) -> CivilDay {
    CivilDay(containing: date, in: zone)
  }

  func start(of day: CivilDay) -> Date {
    if let start = starts[day] { return start }
    let start = day.start(in: zone)
    starts[day] = start
    return start
  }

  func day(_ day: CivilDay) -> PrayerDayAvailability {
    if let availability = days[day] { return availability }
    let availability = schedule.day(day)
    days[day] = availability
    return availability
  }

  /// `end`, no earlier than `start` and no later than ``PrayerSchedule/maximumQueryDays`` days
  /// after the start of `start`'s civil day (section 4.10).
  func clampedEnd(from start: Date, through end: Date) -> Date {
    let limit = self.start(
      of: civilDay(containing: start).adding(days: PrayerSchedule.maximumQueryDays))
    return min(max(end, start), max(limit, start))
  }

  /// The context of a query over `[date, bound]`.
  func context(at date: Date, through bound: Date) -> ScheduleContext {
    context(first: civilDay(containing: date).adding(days: -2), last: civilDay(containing: bound))
  }

  func context(first: CivilDay, last: CivilDay) -> ScheduleContext {
    cached(first: first, last: last).context
  }

  private func cached(at date: Date, through bound: Date) -> CachedContext {
    cached(first: civilDay(containing: date).adding(days: -2), last: civilDay(containing: bound))
  }

  private func cached(first: CivilDay, last: CivilDay) -> CachedContext {
    let key = ContextKey(first: first, last: last)
    if let cached = contexts[key] { return cached }
    let count = max(1, first.days(to: last) + 1)
    let contextDays = (0..<count).map { first.adding(days: $0) }
    let cached = CachedContext(
      ScheduleContext(
        days: contextDays, availability: contextDays.map(day),
        starts: (0..<(count + 2)).map { start(of: first.adding(days: $0)) },
        expectedKinds: expectedKinds))
    contexts[key] = cached
    contextOrder.append(key)
    if contextOrder.count > Self.contextCacheLimit {
      contexts[contextOrder.removeFirst()] = nil
    }
    return cached
  }

  /// The state at `date` through `bound`, which the caller has clamped.
  func state(at date: Date, through bound: Date, policy: StatePolicy) -> ScheduleState {
    let cached = cached(at: date, through: bound)
    let context = cached.context
    let snapshot = context.snapshot(at: date, through: bound, policy: policy)
    let changesAt = changesAt(
      after: date, from: snapshot, candidates: cached.candidates(policy: policy), bound: bound,
      policy: policy)
    let coverage = context.coverage(from: date, through: bound)
    guard snapshot.isAvailable else { return .unavailable(coverage, changesAt: changesAt) }
    return .available(
      PrayerState(
        date: date, previous: snapshot.previous, latestPrayer: snapshot.latestPrayer,
        next: snapshot.next, nextPrayer: snapshot.nextPrayer, justStarted: snapshot.justStarted,
        isApproaching: snapshot.isApproaching, changesAt: changesAt),
      coverage: coverage)
  }

  /// The earliest candidate in `(date, bound]` whose state differs from `snapshot`, each
  /// candidate evaluated in its own context.
  private func changesAt(
    after date: Date, from snapshot: Snapshot, candidates: [Date], bound: Date,
    policy: StatePolicy
  ) -> Date? {
    var index = candidates.partitioningIndex { $0 > date }
    while index < candidates.count, candidates[index] <= bound {
      let candidate = candidates[index]
      let later = self.context(at: candidate, through: bound)
        .snapshot(at: candidate, through: bound, policy: policy)
      if !later.isSameState(as: snapshot) { return candidate }
      index += 1
    }
    return nil
  }

  private struct ContextKey: Hashable {
    var first: CivilDay
    var last: CivilDay
  }

  /// A context with its change candidates, built once per policy.
  private final class CachedContext {
    let context: ScheduleContext
    private var candidatesByPolicy: [StatePolicy: [Date]] = [:]

    init(_ context: ScheduleContext) {
      self.context = context
    }

    func candidates(policy: StatePolicy) -> [Date] {
      if let candidates = candidatesByPolicy[policy] { return candidates }
      let candidates = context.changeCandidates(policy: policy)
      candidatesByPolicy[policy] = candidates
      return candidates
    }
  }
}
