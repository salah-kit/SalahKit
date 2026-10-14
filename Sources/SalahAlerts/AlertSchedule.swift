import Foundation
import SalahCore

/// Fire dates at which alerts of one kind may be due but can't be known, because the source
/// has a gap.
///
/// A source gap is an interval in which events of some prayers may fall, unknown (RFC 0001
/// §4.6). Each kind of alert moves it by its own offset: an unknown Isha makes Isha's alert
/// unknown in the same interval, and its 15-minute before-reminder unknown 15 minutes
/// earlier. The interval is half-open, clipped to the schedule's requested range.
nonisolated public struct AlertGap: Hashable, Sendable {
  /// Where alerts of ``kind`` may fall, from `start` up to but not including `end`.
  public var interval: DateInterval
  /// The kind of alert.
  public var kind: AlertKind
  /// The owning day whose events are unknown.
  public var day: CivilDay
  /// The prayers whose alerts of ``kind`` may fall in the interval.
  public var prayers: Set<PrayerKind>
  /// Why the events are unknown.
  public var reason: ScheduleGapReason

  /// Creates a gap.
  public init(
    interval: DateInterval, kind: AlertKind, day: CivilDay, prayers: Set<PrayerKind>,
    reason: ScheduleGapReason
  ) {
    self.interval = interval
    self.kind = kind
    self.day = day
    self.prayers = prayers
    self.reason = reason
  }
}

/// Every enabled, known alert in a range, without a request cap, and where alerts can't be
/// known.
///
/// ``AlertPlanner/schedule(_:namespace:from:to:maximumReminderOffset:settings:)`` builds it.
/// ``InProcessAlertEngine`` follows it whole;
/// ``AlertPlanner/notificationPlan(_:from:budget:excluding:)``
/// selects from it what an operating system can keep.
nonisolated public struct AlertSchedule: Hashable, Sendable {
  /// The namespace of every alert, kept even when there are none.
  public var namespace: String
  /// The alerts, by fire date, then identity.
  public var alerts: [PlannedAlert]
  /// The half-open fire-date range the schedule covers, after the query limit.
  public var requestedRange: DateInterval
  /// Where alerts can't be known, by start, then owning day, alert kind, reason and end.
  public var gaps: [AlertGap]

  /// Creates a schedule.
  public init(
    namespace: String, alerts: [PlannedAlert], requestedRange: DateInterval, gaps: [AlertGap]
  ) {
    self.namespace = namespace
    self.alerts = alerts
    self.requestedRange = requestedRange
    self.gaps = gaps
  }
}

/// The share of the operating system's pending requests an app gives one namespace, and how
/// the plan spends it.
///
/// Apple keeps a limited number of pending notification requests per app. The app assigns
/// this namespace's allowance after reserving room for its other features; 60 is a default,
/// not a separate allowance for every scheduler. Negative values count as zero.
nonisolated public struct AlertBudget: Hashable, Sendable {
  /// The most requests the plan selects.
  public var maxPending: Int
  /// How far ahead every enabled alert, reminders included, is reserved first.
  public var nearTermWindow: Duration
  /// How far ahead the plan looks at all.
  public var horizon: Duration

  /// Creates a budget: by default 60 requests, a two-day near-term window and a 14-day
  /// horizon.
  public init(
    maxPending: Int = 60, nearTermWindow: Duration = .seconds(2 * 86_400),
    horizon: Duration = .seconds(14 * 86_400)
  ) {
    self.maxPending = maxPending
    self.nearTermWindow = nearTermWindow
    self.horizon = horizon
  }
}

/// The alerts to request from the operating system, and how far they're complete.
nonisolated public struct NotificationPlan: Hashable, Sendable {
  /// The namespace the plan belongs to, kept even when there are no alerts.
  public var namespace: String
  /// The half-open fire-date range alerts were selected from: from the planning instant to
  /// the end of the requested range or the horizon, whichever comes first.
  public var effectiveRange: DateInterval
  /// The selected alerts, by fire date, then identity.
  public var alerts: [PlannedAlert]
  /// Every enabled alert before this instant is known and either in ``alerts`` or excluded
  /// by its handled-occurrence record.
  ///
  /// It ends the contiguous interval from the planning instant in which the plan is complete:
  /// at the first enabled alert the budget left out, the first instant a source gap could
  /// hide one, or the effective range's end. It isn't the last selected alert's fire date.
  public var coveredUntil: Date
  /// Each alert kind's own cutoff, for the kinds the schedule has; ``coveredUntil`` is the
  /// earliest.
  public var coverageByKind: [AlertKind: Date]

  /// Creates a plan.
  public init(
    namespace: String, effectiveRange: DateInterval, alerts: [PlannedAlert], coveredUntil: Date,
    coverageByKind: [AlertKind: Date]
  ) {
    self.namespace = namespace
    self.effectiveRange = effectiveRange
    self.alerts = alerts
    self.coveredUntil = coveredUntil
    self.coverageByKind = coverageByKind
  }
}

/// Why the planner can't build an alert schedule.
nonisolated public enum AlertPlanningError: Error, Hashable, Sendable {
  /// The namespace is empty or contains `/`.
  case invalidNamespace(String)
  /// The maximum reminder offset is negative or longer than
  /// ``AlertPlanner/reminderOffsetLimit``.
  case invalidMaximumReminderOffset(Duration)
  /// The settings for a subject give a reminder offset that isn't positive or is longer than
  /// the maximum reminder offset.
  case reminderOffsetOutOfRange(AlertSubject, AlertKind, Duration)
}
