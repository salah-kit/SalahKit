import Foundation
import SalahCore
import SalahWidgets
import WidgetKit

/// One widget entry: when it starts, what it shows, and what plays.
nonisolated struct MenuBarEntry: TimelineEntry, Hashable, Sendable {
  var date: Date
  var content: Content
  /// What played when the timeline was built. The app reloads the widget whenever it changes,
  /// so every entry of a timeline carries the same value.
  var nowPlaying: NowPlaying?

  /// What an entry shows.
  enum Content: Hashable, Sendable {
    /// No settings in the App Group yet: the app hasn't run.
    case setupRequired
    /// A state of the timeline, with the language, place and listed day.
    case timeline(PrayerTimelineState, Context)
  }

  /// What the views need besides the state.
  struct Context: Hashable, Sendable {
    var language: NamesLanguage
    var place: Place
    /// The owning day that is the entry's civil date in the place's zone.
    var day: PrayerDayAvailability
  }

  /// Whether the entry shows the Stop button.
  var showsStopButton: Bool { nowPlaying != nil }
}

/// The widget's timeline logic: a pure function of the stored values and the moment, run by the
/// extension's provider, by the tests with a fixed clock, and by the stop harness.
nonisolated enum MenuBarTimeline {
  /// Static text, as the menu bar's title: a minute grid within 30 minutes of a prayer, a
  /// 15-minute grid elsewhere. SalahWidgets ends the timeline where 96 entries run out.
  static let strategy = RefreshStrategy.steps(
    fine: .seconds(60), coarse: .seconds(15 * 60), window: .seconds(30 * 60))

  /// The entries from `now`, and when to ask for the next timeline.
  ///
  /// Without settings: one setup entry, and no reload until the app asks. With settings: the
  /// entries of SalahWidgets' `.steps` timeline, ending with its expired entry, plus an entry at
  /// each midnight in the place's zone, so the listed day turns over with the date.
  static func timeline(
    settings: MenuBarSettings?, nowPlaying: NowPlaying?, now: Date
  ) -> (entries: [MenuBarEntry], reloadDate: Date?) {
    guard let settings else {
      return ([MenuBarEntry(date: now, content: .setupRequired, nowPlaying: nowPlaying)], nil)
    }
    let schedule = settings.schedule
    let zone = settings.place.location.timeZone
    func entry(_ date: Date, _ state: PrayerTimelineState) -> MenuBarEntry {
      MenuBarEntry(
        date: date,
        content: .timeline(
          state,
          MenuBarEntry.Context(
            language: settings.language, place: settings.place,
            day: schedule.day(containing: date))),
        nowPlaying: nowPlaying)
    }
    guard
      let planned = try? PrayerTimelineBuilder(schedule: schedule, strategy: strategy)
        .timeline(from: now)
    else {
      // Only an invalid horizon fails, and the default one is valid.
      return ([entry(now, .expired(knownThrough: now))], nil)
    }
    var entries: [MenuBarEntry] = []
    for (index, item) in planned.entries.enumerated() {
      entries.append(entry(item.date, item.state))
      guard index + 1 < planned.entries.count, case .schedule = item.state else { continue }
      var midnight = CivilDay(containing: item.date, in: zone).adding(days: 1).start(in: zone)
      while midnight < planned.entries[index + 1].date {
        entries.append(entry(midnight, item.state))
        midnight = CivilDay(containing: midnight, in: zone).adding(days: 1).start(in: zone)
      }
    }
    return (entries, planned.reloadDate)
  }
}
