import Foundation
import SalahCore

/// Turns a prayer schedule and an app's alert settings into alerts.
///
/// Planning has two steps. ``schedule(_:namespace:from:to:maximumReminderOffset:settings:)``
/// builds the complete ``AlertSchedule`` of a range: every enabled alert, and the gaps where a
/// missing prayer time hides some. ``notificationPlan(_:from:budget:)`` selects what an
/// operating system can keep: every alert of the near term, then at-time alerts as far as the
/// budget reaches, and says until when that selection is complete.
///
/// ```swift
/// let alerts = try AlertPlanner().schedule(
///   schedule, namespace: "prayers", from: now, to: now.addingTimeInterval(14 * 86_400),
///   settings: { subject in
///     subject.prayer.isPrayer ? AlertSettings(before: .seconds(10 * 60)) : nil
///   })
/// let plan = AlertPlanner().notificationPlan(alerts, from: now)
/// ```
///
/// The planner never invents an alert. A prayer time the source doesn't know gets none, and
/// it ends the plan's coverage where its alerts could have fallen. RFC 0003 §4.3 and §4.4
/// define both steps.
nonisolated public struct AlertPlanner: Sendable {
  /// The longest `maximumReminderOffset` the planner accepts: seven days.
  public static let reminderOffsetLimit: Duration = .seconds(7 * 86_400)

  /// Creates a planner.
  public init() {}

  /// Every enabled alert whose fire date is in `[start, end)`, and the gaps where alerts can't
  /// be known.
  ///
  /// The planner reads `schedule.events(from: start − m, through: end + m)` once, where `m` is
  /// `maximumReminderOffset`: enough to find the after-reminders of earlier prayers and the
  /// before-reminders of later ones. For each event it asks `settings` about its subject and
  /// places the alerts they enable. For each gap in that query's coverage, it asks about the
  /// prayers the gap hides (both observances for a Friday's Dhuhr) and moves the gap by each
  /// enabled kind's offset. An end before the start counts as the start, and a range that
  /// SalahCore's query limit cuts short ends early, as ``AlertSchedule/requestedRange`` shows.
  ///
  /// - Parameters:
  ///   - schedule: The prayer schedule.
  ///   - namespace: The namespace of every alert: not empty, and no `/`.
  ///   - start: The first fire date. An app that runs alerts in process includes its catch-up
  ///     interval: `now − 5 minutes`.
  ///   - end: The end of the range, excluded.
  ///   - maximumReminderOffset: The longest reminder offset the app allows, at most
  ///     ``reminderOffsetLimit``.
  ///   - settings: The settings for a subject, or `nil` for no alerts.
  /// - Throws: ``AlertPlanningError``: an invalid namespace, an invalid maximum, or settings
  ///   with a reminder offset that isn't positive or exceeds the maximum.
  public func schedule(
    _ schedule: PrayerSchedule, namespace: String, from start: Date, to end: Date,
    maximumReminderOffset: Duration = .seconds(2 * 3_600),
    settings: (AlertSubject) -> AlertSettings?
  ) throws(AlertPlanningError) -> AlertSchedule {
    guard NotificationIdentity.isValidNamespace(namespace) else {
      throw .invalidNamespace(namespace)
    }
    guard maximumReminderOffset >= .zero, maximumReminderOffset <= Self.reminderOffsetLimit
    else { throw .invalidMaximumReminderOffset(maximumReminderOffset) }

    let margin = maximumReminderOffset.timeInterval
    var end = max(end, start)
    let query = schedule.events(
      from: start.addingTimeInterval(-margin), through: end.addingTimeInterval(margin))
    // SalahCore's query limit (RFC 0001 §4.10) can end the query early; then so does the range.
    if query.coverage.requested.end < end.addingTimeInterval(margin) {
      end = max(start, query.coverage.requested.end.addingTimeInterval(-margin))
    }

    func checked(_ subject: AlertSubject) throws(AlertPlanningError) -> AlertSettings? {
      guard let value = settings(subject) else { return nil }
      for (kind, offset) in [(AlertKind.before, value.before), (.after, value.after)] {
        if let offset, offset <= .zero || offset > maximumReminderOffset {
          throw .reminderOffsetOutOfRange(subject, kind, offset)
        }
      }
      return value
    }

    var alerts: [PlannedAlert] = []
    for event in query.events {
      let subject = AlertSubject(
        scheduleDay: event.scheduleDay, prayer: event.kind, observance: event.observance)
      guard let value = try checked(subject) else { continue }
      for alert in value.enabledAlerts {
        let fireDate = event.time.addingTimeInterval(alert.offset)
        guard start <= fireDate, fireDate < end else { continue }
        alerts.append(
          PlannedAlert(
            id: NotificationIdentity(
              namespace: namespace, scheduleDay: event.scheduleDay, prayer: event.kind,
              kind: alert.kind),
            event: event, fireDate: fireDate, sound: alert.sound))
      }
    }
    alerts.sort(by: PlannedAlert.precedes)

    var grouped: [GapKey: Set<PrayerKind>] = [:]
    for gap in query.coverage.gaps {
      for prayer in gap.kinds.sorted() {
        // A source could have declared Jumu'ah on a Friday's Dhuhr, so both settings count.
        let observances: [PrayerObservance] =
          prayer == .dhuhr && gap.day.weekday == 6 ? [.ordinary, .jumuah] : [.ordinary]
        for observance in observances {
          let subject = AlertSubject(scheduleDay: gap.day, prayer: prayer, observance: observance)
          guard let value = try checked(subject) else { continue }
          for alert in value.enabledAlerts {
            let lower = max(gap.interval.start.addingTimeInterval(alert.offset), start)
            let upper = min(gap.interval.end.addingTimeInterval(alert.offset), end)
            guard lower < upper else { continue }
            let key = GapKey(
              lower: lower, upper: upper, kind: alert.kind, day: gap.day, reason: gap.reason)
            grouped[key, default: []].insert(prayer)
          }
        }
      }
    }
    let gaps = grouped.sorted { $0.key.precedes($1.key) }.map { key, prayers in
      AlertGap(
        interval: DateInterval(start: key.lower, end: key.upper), kind: key.kind, day: key.day,
        prayers: prayers, reason: key.reason)
    }
    return AlertSchedule(
      namespace: namespace, alerts: alerts, requestedRange: DateInterval(start: start, end: end),
      gaps: gaps)
  }

  /// The alerts to request from the operating system at `now`, within `budget`.
  ///
  /// Only alerts that fire in `[now, E)` can be selected, where `E` is the end of the
  /// schedule's range or `now + budget.horizon`, whichever comes first. Every alert of the
  /// near-term window is reserved first, of every kind, in order; if they don't all fit, the
  /// earliest are kept. The rest of the budget goes to the at-time alerts after the window,
  /// nearest first. Later reminders are never selected: they stay in the schedule for
  /// ``InProcessAlertEngine``.
  ///
  /// Each kind's coverage ends at its first alert left out, at the first instant a gap could
  /// hide one (a gap that holds `now` ends it at `now`; one entirely before `now` doesn't
  /// count), or at `E`. ``NotificationPlan/coveredUntil`` is the earliest, and `now` when the
  /// schedule's range starts after `now`.
  public func notificationPlan(
    _ schedule: AlertSchedule, from now: Date, budget: AlertBudget = AlertBudget()
  ) -> NotificationPlan {
    let allowance = max(0, budget.maxPending)
    let requested = schedule.requestedRange
    let effectiveEnd = max(
      now, min(requested.end, now.addingTimeInterval(max(0, budget.horizon.timeInterval))))
    let nearEnd = min(
      now.addingTimeInterval(max(0, budget.nearTermWindow.timeInterval)), effectiveEnd)

    let inRange = schedule.alerts
      .filter { now <= $0.fireDate && $0.fireDate < effectiveEnd }
      .sorted(by: PlannedAlert.precedes)
    // Sorted by fire date, the near-term alerts are a prefix.
    let nearCount = inRange.prefix { $0.fireDate < nearEnd }.count
    var selected = Array(repeating: false, count: inRange.count)
    if nearCount > allowance {
      for index in 0..<allowance { selected[index] = true }
    } else {
      for index in 0..<nearCount { selected[index] = true }
      var room = allowance - nearCount
      for index in nearCount..<inRange.count where room > 0 && inRange[index].kind == .atTime {
        selected[index] = true
        room -= 1
      }
    }

    let kinds = Set(schedule.alerts.map(\.kind)).union(schedule.gaps.map(\.kind))
    var coverage: [AlertKind: Date] = [:]
    for kind in kinds {
      // Nothing is known before a range that starts after now.
      guard requested.start <= now else {
        coverage[kind] = now
        continue
      }
      var cutoff = effectiveEnd
      if let first = inRange.indices.first(where: { inRange[$0].kind == kind && !selected[$0] }) {
        cutoff = min(cutoff, inRange[first].fireDate)
      }
      for gap in schedule.gaps
      where gap.kind == kind && gap.interval.start < effectiveEnd && gap.interval.end > now {
        cutoff = min(cutoff, max(now, gap.interval.start))
      }
      coverage[kind] = cutoff
    }
    let coveredUntil =
      requested.start > now ? now : coverage.values.reduce(effectiveEnd) { min($0, $1) }

    return NotificationPlan(
      namespace: schedule.namespace, effectiveRange: DateInterval(start: now, end: effectiveEnd),
      alerts: inRange.indices.filter { selected[$0] }.map { inRange[$0] },
      coveredUntil: coveredUntil, coverageByKind: coverage)
  }

  /// A transformed gap's bounds and labels, which group its prayers.
  private struct GapKey: Hashable {
    var lower: Date
    var upper: Date
    var kind: AlertKind
    var day: CivilDay
    var reason: ScheduleGapReason

    /// Start, then owning day, alert kind, reason in declaration order and end.
    func precedes(_ other: GapKey) -> Bool {
      if lower != other.lower { return lower < other.lower }
      if day != other.day { return day < other.day }
      if kind != other.kind { return kind < other.kind }
      if reason != other.reason { return reason.declarationOrder < other.reason.declarationOrder }
      return upper < other.upper
    }
  }
}

nonisolated extension ScheduleGapReason {
  /// The position in declaration order (RFC 0001 §4.6).
  var declarationOrder: Int {
    switch self {
    case .noPublishedData: 0
    case .calculationUnavailable: 1
    case .invalidData: 2
    case .unresolvedWallTime: 3
    }
  }
}
