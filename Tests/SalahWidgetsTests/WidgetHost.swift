import Foundation
import SalahCore
import Testing

@testable import SalahWidgets

/// A model of how WidgetKit uses a timeline provider, for fixed-clock tests.
///
/// It calls the provider at the start, then at each timeline's reload date plus a chosen delay,
/// or earlier when the app asks for a reload. Between calls it shows the latest timeline's last
/// entry whose date has passed. This is the contract WidgetKit documents, not its actual
/// scheduling: tests check what the supplied entries would show under it, never when the system
/// would show them.
struct WidgetHost {
  /// One provider call and the timeline it returned.
  struct Call {
    var date: Date
    var timeline: PrayerTimeline
    /// The schedule the provider read at the call.
    var schedule: PrayerSchedule
  }

  /// The provider's calls, in date order.
  private(set) var calls: [Call] = []

  /// Runs the provider from `start` until `end`.
  ///
  /// - Parameters:
  ///   - start: The first call.
  ///   - end: The end of the run.
  ///   - delays: Extra seconds after a timeline's reload date before the next call, by the index
  ///     of the call that made the timeline. A late call is how a busy system behaves.
  ///   - appReloads: Dates at which the app saves new inputs and asks for a reload; the next call
  ///     happens then, whatever the reload date.
  ///   - provider: Builds the timeline at a call's date and says what it read.
  init(
    from start: Date, until end: Date, delays: [Int: TimeInterval] = [:], appReloads: [Date] = [],
    provider: (Date) throws -> (PrayerTimeline, PrayerSchedule)
  ) rethrows {
    var date = start
    while date < end {
      let (timeline, schedule) = try provider(date)
      calls.append(Call(date: date, timeline: timeline, schedule: schedule))
      var next = timeline.reloadDate.addingTimeInterval(delays[calls.count - 1] ?? 0)
      if let reload = appReloads.filter({ $0 > date && $0 < next }).min() {
        next = reload
      }
      guard next > date else {
        Issue.record("the next call, \(next), isn't after the call at \(date)")
        break
      }
      date = next
    }
  }

  /// The call whose timeline is showing at `date`.
  func call(at date: Date) -> Call? {
    calls.last { $0.date <= date }
  }

  /// The entry showing at `date`, and the call that supplied it.
  func displayed(at date: Date) -> (call: Call, entry: PrayerTimeline.Entry)? {
    guard let call = call(at: date),
      let entry = call.timeline.entries.last(where: { $0.date <= date })
    else { return nil }
    return (call, entry)
  }
}

/// The parts of a schedule state a widget shows: availability, the five event fields and the
/// approaching flag. The moment, the coverage's requested interval and `changesAt` depend on
/// where a state was computed, not on what it says.
struct ShownState: Hashable, CustomStringConvertible {
  var isAvailable: Bool
  var previous: String?
  var latestPrayer: String?
  var next: String?
  var nextPrayer: String?
  var justStarted: String?
  var isApproaching: Bool

  init(_ state: ScheduleState) {
    let prayer = state.prayerState
    isAvailable = prayer != nil
    previous = prayer?.previous?.id
    latestPrayer = prayer?.latestPrayer?.id
    next = prayer?.next?.id
    nextPrayer = prayer?.nextPrayer?.id
    justStarted = prayer?.justStarted?.id
    isApproaching = prayer?.isApproaching ?? false
  }

  var description: String {
    "available: \(isAvailable), next prayer: \(nextPrayer ?? "nil"), latest: \(latestPrayer ?? "nil"), "
      + "just started: \(justStarted ?? "nil"), approaching: \(isApproaching)"
  }
}

extension PrayerTimeline {
  /// The lookahead bound the timeline's states use: the start of the second civil day after the
  /// horizon's end, in the location's zone (RFC 0001 §4.8).
  func lookahead(in timeZone: TimeZone) -> Date {
    CivilDay(containing: horizon.end, in: timeZone).adding(days: 2).start(in: timeZone)
  }
}
