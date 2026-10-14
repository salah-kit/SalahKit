import Foundation
import SalahCore

/// A bounded widget timeline: refresh-plan entries, optional civil-day boundary entries,
/// a final timeline-expired entry, and the date to ask for the next timeline.
///
/// ``PrayerTimelineBuilder`` makes it. WidgetKit's `Timeline` is built from it by
/// ``PrayerTimelineBuilder/timeline(from:horizon:entry:)``; use this value directly to inspect
/// the entries in a test, or to choose your own reload policy.
///
/// The entries are in date order. Every entry but the last is a ``PrayerTimelineState/schedule(_:)``
/// state, which holds from its date until the next entry's. The last entry is
/// ``PrayerTimelineState/expired(knownThrough:)`` at ``validUntil``: a widget that WidgetKit
/// doesn't reload in time shows that its times ran out instead of a countdown that ended long
/// ago.
nonisolated public struct PrayerTimeline: Hashable, Sendable {
  /// One timeline entry.
  public struct Entry: Hashable, Sendable {
    /// When WidgetKit may start showing the entry.
    public var date: Date
    /// What the entry shows.
    public var state: PrayerTimelineState

    /// Creates an entry.
    public init(date: Date, state: PrayerTimelineState) {
      self.date = date
      self.state = state
    }
  }

  /// The interval the timeline was asked to cover, after SalahCore's query limit: from the
  /// first entry's date to the requested horizon's end.
  public var horizon: DateInterval

  /// The entries in date order, ending with the timeline-expired entry at ``validUntil``.
  public var entries: [Entry]

  /// Where the timeline's validity ends and its expired entry starts: ``horizon``'s end, or an
  /// earlier date when the entry limit couldn't hold every change before it.
  public var validUntil: Date

  /// When to ask WidgetKit for the next timeline: halfway from the first entry to
  /// ``validUntil``, which leaves the second half as slack for a late reload.
  public var reloadDate: Date

  /// Whether the entry limit ended the timeline before ``horizon``'s end.
  public var isTruncated: Bool { validUntil < horizon.end }
}
