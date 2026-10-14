import Foundation
import SalahCore

/// What a widget entry shows: the schedule's state at the entry's date, or the end of the
/// timeline's validity.
///
/// The two cases answer different questions, and a widget should word them differently:
/// - ``schedule(_:)`` carries what the schedule knows. Its state can be complete, partial (a
///   known previous prayer with an unknown next one) or `ScheduleState.unavailable`
///   when the source has no usable data, such as a timetable that ended. Reloading the widget
///   can't fix a source gap; only new data from the app can. A calculation that can't produce
///   a kind, such as Maghrib in a polar summer, leaves the state unavailable across that
///   kind's whole window, so the partial state comes from a published timetable that ends.
/// - ``expired(knownThrough:)`` means the timeline ran out before WidgetKit asked for a new one.
///   The source may be fine, even a calculation that never ends. Show that the times need
///   refreshing, never a countdown that would be stale.
nonisolated public enum PrayerTimelineState: Hashable, Sendable {
  /// The schedule's state at the entry's date, with the coverage up to the timeline's lookahead.
  case schedule(ScheduleState)
  /// The timeline's validity ended at `knownThrough`. Nothing after that instant was planned.
  case expired(knownThrough: Date)

  /// The known prayer state, when the entry has one: `nil` for an unavailable schedule state
  /// and for an expired timeline.
  public var prayerState: PrayerState? {
    if case .schedule(let state) = self { return state.prayerState }
    return nil
  }
}
