import Foundation
import SalahCore

/// Builds bounded widget timelines from a schedule, inside the widget extension.
///
/// The extension loads the app's inputs, builds a ``PrayerSchedule`` and asks the builder for a
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
/// entries come from SalahCore's ``PrayerSchedule/refreshPlan(from:through:strategy:policy:limit:)``:
/// one wherever the known state or its coverage changes, so a source gap, such as a timetable
/// that ends, appears as a ``PrayerTimelineState/schedule(_:)`` state at its boundary. The last
/// entry is always ``PrayerTimelineState/expired(knownThrough:)``, even for a calculation that
/// never runs out, and the timeline asks WidgetKit for the next one halfway to it. When the
/// entry limit can't hold every change in the horizon, the timeline ends at the first change it
/// can't hold, and ``PrayerTimeline/validUntil`` says so.
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

  /// How the entries' dates are chosen: ``RefreshStrategy/stateChanges`` for views that count
  /// down by themselves, or ``RefreshStrategy/steps(fine:coarse:window:)`` for static text.
  public let strategy: RefreshStrategy

  /// The most entries a timeline holds, the expired entry included.
  public let limit: Int

  /// Creates a builder.
  ///
  /// - Parameters:
  ///   - schedule: The schedule the entries describe.
  ///   - policy: When a prayer counts as approaching or just started.
  ///   - strategy: How the entries' dates are chosen.
  ///   - limit: The most entries a timeline holds, the expired entry included. It must be at
  ///     least 2.
  public init(
    schedule: PrayerSchedule, policy: StatePolicy = StatePolicy(),
    strategy: RefreshStrategy = .stateChanges, limit: Int = 96
  ) {
    self.schedule = schedule
    self.policy = policy
    self.strategy = strategy
    self.limit = limit
  }

  /// The timeline from `now` through `now + horizon`.
  ///
  /// The entries are the refresh plan's entries, each with its schedule state, followed by
  /// ``PrayerTimelineState/expired(knownThrough:)`` at ``PrayerTimeline/validUntil``. The
  /// reload date is halfway from `now` to `validUntil`.
  ///
  /// - Parameters:
  ///   - now: The first entry's date, usually the moment WidgetKit asked for the timeline.
  ///   - horizon: How far the timeline looks ahead. SalahCore clamps a horizon beyond
  ///     ``PrayerSchedule/maximumQueryDays`` days.
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
    let entries =
      plan.entries.map { PrayerTimeline.Entry(date: $0.date, state: .schedule($0.state)) }
      + [
        PrayerTimeline.Entry(date: plan.validUntil, state: .expired(knownThrough: plan.validUntil))
      ]
    return PrayerTimeline(
      horizon: plan.horizon, entries: entries, validUntil: plan.validUntil,
      reloadDate: start.addingTimeInterval(plan.validUntil.timeIntervalSince(start) / 2))
  }

  /// A duration in seconds; a duration too long for a `Double` to count exactly is still far
  /// beyond SalahCore's query limit.
  private static func seconds(of duration: Duration) -> TimeInterval {
    let parts = duration.components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}
