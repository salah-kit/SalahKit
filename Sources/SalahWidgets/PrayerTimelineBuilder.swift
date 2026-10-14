import Foundation
import SalahCore

/// Builds bounded widget timelines from a schedule, inside the widget extension.
///
/// The extension loads the app's inputs, builds a `PrayerSchedule` and asks the builder for a
/// timeline. Nothing depends on the app having run since the last timeline, so a calculated
/// widget keeps going for as long as WidgetKit keeps asking:
///
/// ```swift
/// let schedule = PrayerSchedule(source: CalculationSource(settings.calculation),
///                               location: settings.location)
/// let builder = PrayerTimelineBuilder(schedule: schedule)
/// completion(builder.timeline(from: .now) { date, state in
///   PrayerEntry(date: date, state: state)
/// })
/// ```
///
/// A timeline covers ``defaultHorizon`` (48 hours) unless you ask for another horizon. Its
/// entries come from SalahCore's `PrayerSchedule.refreshPlan`:
/// one wherever the known state or its coverage changes, so a source gap, such as a timetable
/// that ends, appears as a ``PrayerTimelineState/schedule(_:)`` state at its boundary. The last
/// entry is always ``PrayerTimelineState/expired(knownThrough:)``, even for a calculation that
/// never runs out, and the timeline asks WidgetKit for the next one halfway to it. When the
/// entry limit can't hold every change in the horizon, the timeline ends at the first change it
/// can't hold, and ``PrayerTimeline/validUntil`` says so.
/// Set ``includeDayBoundaries`` for a widget that lists the current day's prayers: the timeline
/// then also changes at each civil day's start in the schedule's time zone.
///
/// The dates say when the content changes. WidgetKit still decides when it shows an entry and
/// when it asks for the next timeline.
nonisolated public struct PrayerTimelineBuilder: Sendable {
  /// The horizon a timeline covers unless you choose another: 48 hours.
  public static let defaultHorizon: Duration = .seconds(48 * 3_600)

  /// The schedule the entries describe.
  public let schedule: PrayerSchedule

  /// When a prayer counts as approaching or just started.
  public let policy: StatePolicy

  /// How the entries' dates are chosen: `RefreshStrategy.stateChanges` for views that count
  /// down by themselves, or `RefreshStrategy.steps` for static text.
  public let strategy: RefreshStrategy

  /// Whether entries also mark the starts of civil days in the schedule's time zone.
  ///
  /// Enable this for a widget that lists the current day's prayers. A day starts at local
  /// midnight, or the first valid instant after it when a clock change skips midnight. These
  /// entries use the same policy and lookahead as the refresh plan and count toward ``limit``.
  public let includeDayBoundaries: Bool

  /// The most entries a timeline holds, the expired entry included.
  public let limit: Int

  /// Creates a builder.
  ///
  /// - Parameters:
  ///   - schedule: The schedule the entries describe.
  ///   - policy: When a prayer counts as approaching or just started.
  ///   - strategy: How the entries' dates are chosen.
  ///   - includeDayBoundaries: Whether to add entries at civil-day starts in the schedule's
  ///     time zone, so a list of today's prayers turns over with the date. Defaults to `false`.
  ///   - limit: The most entries a timeline holds, the expired entry included. It must be at
  ///     least 2.
  public init(
    schedule: PrayerSchedule, policy: StatePolicy = StatePolicy(),
    strategy: RefreshStrategy = .stateChanges, includeDayBoundaries: Bool = false, limit: Int = 96
  ) {
    self.schedule = schedule
    self.policy = policy
    self.strategy = strategy
    self.includeDayBoundaries = includeDayBoundaries
    self.limit = limit
  }

  /// The timeline from `now` through `now + horizon`.
  ///
  /// The entries are the refresh plan's dates, also civil-day starts when
  /// ``includeDayBoundaries`` is enabled, each with the state at that instant. Dates are
  /// deduplicated before applying ``limit``, with one slot reserved for
  /// ``PrayerTimelineState/expired(knownThrough:)`` at ``PrayerTimeline/validUntil``. When the
  /// dates don't fit, validity ends at the first omitted date. The reload date is halfway from
  /// `now` to `validUntil`.
  ///
  /// - Parameters:
  ///   - now: The first entry's date, usually the moment WidgetKit asked for the timeline.
  ///   - horizon: How far the timeline looks ahead. SalahCore clamps a horizon beyond
  ///     `PrayerSchedule.maximumQueryDays` days.
  /// - Returns: The timeline.
  /// - Throws: `RefreshPlanError` for a horizon that isn't positive, a ``limit`` below 2 or a
  ///   `steps` strategy with a step under a second or a negative window.
  public func timeline(
    from now: Date, horizon: Duration = defaultHorizon
  ) throws(RefreshPlanError) -> PrayerTimeline {
    let plan = try schedule.refreshPlan(
      from: now, through: now.addingTimeInterval(Self.seconds(of: horizon)), strategy: strategy,
      policy: policy, limit: limit)
    let start = plan.horizon.start
    let zone = schedule.location.timeZone
    var dates = Set(plan.dates)
    if includeDayBoundaries {
      var day = CivilDay(containing: start, in: zone).adding(days: 1)
      let lastDay = CivilDay(containing: plan.validUntil, in: zone)
      while day <= lastDay {
        let boundary = day.start(in: zone)
        if boundary > start && boundary < plan.validUntil { dates.insert(boundary) }
        // Advance the civil date rather than the instant: a skipped date can have the same
        // start as its successor, and a day around DST needn't last 24 hours.
        day = day.adding(days: 1)
      }
    }
    let ordered = dates.sorted()
    let validUntil = ordered.count >= limit ? ordered[limit - 1] : plan.validUntil
    let states = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.date, $0.state) })
    // Match Core's lookahead from the clamped horizon, even if the entry budget ends sooner.
    let lookahead = CivilDay(containing: plan.horizon.end, in: zone).adding(days: 2).start(in: zone)
    let entries =
      ordered.prefix(limit - 1).map { date in
        PrayerTimeline.Entry(
          date: date,
          state: .schedule(
            states[date] ?? schedule.state(at: date, through: lookahead, policy: policy)))
      }
      + [
        PrayerTimeline.Entry(date: validUntil, state: .expired(knownThrough: validUntil))
      ]
    return PrayerTimeline(
      horizon: plan.horizon, entries: entries, validUntil: validUntil,
      reloadDate: start.addingTimeInterval(validUntil.timeIntervalSince(start) / 2))
  }

  /// A duration in seconds; a duration too long for a `Double` to count exactly is still far
  /// beyond SalahCore's query limit.
  private static func seconds(of duration: Duration) -> TimeInterval {
    let parts = duration.components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}
