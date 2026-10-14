import Foundation
import SalahCore
import SalahWidgets
import WidgetKit

/// One widget entry: when it starts and what it shows.
nonisolated struct PrayerEntry: TimelineEntry, Hashable, Sendable {
  var date: Date
  var content: EntryContent
}

/// What an entry shows: the setup prompt, or a state of the timeline with what the views need
/// to draw it.
nonisolated enum EntryContent: Hashable, Sendable {
  /// No settings in the App Group yet: the app hasn't been set up. The wording follows the
  /// device's language, the only one known.
  case setupRequired(NamesLanguage)
  /// A state of the timeline: the schedule's state (available, partial or unavailable) or the
  /// end of the timeline's validity.
  case timeline(PrayerTimelineState, EntryContext)
}

/// What the views need besides the state.
nonisolated struct EntryContext: Hashable, Sendable {
  /// The language of the names and the wording.
  var language: NamesLanguage
  /// The place, whose time zone every time is shown in.
  var place: Place
  /// The owning day that is the entry's civil date in the place's zone: the day the medium and
  /// large widgets list.
  var day: PrayerDayAvailability
}

/// The timeline the provider hands to WidgetKit, as plain values a test can inspect.
nonisolated struct WidgetTimeline: Hashable, Sendable {
  /// When to ask for the next timeline.
  enum Reload: Hashable, Sendable {
    /// Only when the app asks: the widget waits for setup.
    case never
    /// At this date.
    case after(Date)
  }

  /// The entries, in date order.
  var entries: [PrayerEntry]
  /// When to ask for the next timeline.
  var reload: Reload
  /// SalahWidgets' timeline the entries came from; `nil` when the widget waits for setup or
  /// the timeline couldn't be planned.
  var prayerTimeline: PrayerTimeline?

  /// The timeline for WidgetKit.
  var widgetKitTimeline: Timeline<PrayerEntry> {
    switch reload {
    case .never: Timeline(entries: entries, policy: .never)
    case .after(let date): Timeline(entries: entries, policy: .after(date))
    }
  }
}

/// The widget's timeline logic: a pure function of the settings and the moment, run by the
/// extension's `TimelineProvider` and by the tests with a fixed clock.
nonisolated enum PrayerTimelineProvider {
  /// The timeline from `now`.
  ///
  /// Without settings, one setup-required entry and no reload until the app saves settings and
  /// asks for one. With settings, the extension builds its own schedule and SalahWidgets'
  /// `.stateChanges` timeline over the default 48-hour horizon: an entry wherever the state
  /// changes and at each civil-day start in the place's zone, the timeline-expired entry at
  /// its end, and a reload halfway there. The builder's day boundaries turn over the listed
  /// day with the date.
  ///
  /// - Parameters:
  ///   - settings: The settings from the App Group, or `nil` when there are none.
  ///   - now: The moment WidgetKit asked for the timeline.
  ///   - deviceLanguage: The language of the setup prompt.
  ///   - horizon: How far the timeline looks ahead.
  static func timeline(
    settings: WidgetSettings?, now: Date, deviceLanguage: NamesLanguage = .english,
    horizon: Duration = PrayerTimelineBuilder.defaultHorizon
  ) -> WidgetTimeline {
    guard let settings else {
      return WidgetTimeline(
        entries: [PrayerEntry(date: now, content: .setupRequired(deviceLanguage))],
        reload: .never, prayerTimeline: nil)
    }
    let schedule = settings.schedule
    func context(at date: Date) -> EntryContext {
      EntryContext(
        language: settings.language, place: settings.place,
        day: schedule.day(containing: date))
    }

    let planned: PrayerTimeline
    do {
      planned = try PrayerTimelineBuilder(schedule: schedule, includeDayBoundaries: true)
        .timeline(from: now, horizon: horizon)
    } catch {
      // Only an invalid horizon fails; show the problem until the app reloads the widget, as
      // SalahWidgets' own WidgetKit timeline does.
      return WidgetTimeline(
        entries: [
          PrayerEntry(date: now, content: .timeline(.expired(knownThrough: now), context(at: now)))
        ],
        reload: .never, prayerTimeline: nil)
    }

    let entries = planned.entries.map { entry in
      PrayerEntry(date: entry.date, content: .timeline(entry.state, context(at: entry.date)))
    }
    return WidgetTimeline(
      entries: entries, reload: .after(planned.reloadDate), prayerTimeline: planned)
  }
}
