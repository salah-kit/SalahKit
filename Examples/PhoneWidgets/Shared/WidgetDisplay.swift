import Foundation
import SalahCore
import SalahWidgets

/// What a widget entry shows, decided before any view draws it.
///
/// The cases follow the questions a person asks of the widget, and each has its own wording:
/// - ``setupRequired``: the app hasn't saved settings yet.
/// - ``times(_:)``: the schedule knows something. A partial state keeps the known times and
///   says which aren't known; it never counts down to a prayer it doesn't know.
/// - ``unavailable(_:)``: the schedule knows nothing usable at this moment, and why.
/// - ``expired(knownThrough:)``: the timeline ran out before WidgetKit asked for a new one. The
///   times need refreshing; no countdown.
nonisolated enum WidgetDisplay: Hashable, Sendable {
  case setupRequired
  case times(TimesDisplay)
  case unavailable(UnavailableReason)
  case expired(knownThrough: Date)

  /// The display of an entry's content.
  init(_ content: EntryContent) {
    switch content {
    case .setupRequired:
      self = .setupRequired
    case .timeline(.expired(let knownThrough), _):
      self = .expired(knownThrough: knownThrough)
    case .timeline(.schedule(.unavailable(let coverage, _)), _):
      self = .unavailable(UnavailableReason(coverage.gaps.map(\.reason)))
    case .timeline(.schedule(.available(let state, _)), let context):
      self = .times(TimesDisplay(state: state, day: context.day))
    }
  }
}

/// A known state, with the listed day and what it lacks.
nonisolated struct TimesDisplay: Hashable, Sendable {
  /// The state: its next prayer is `nil` when the schedule can't name it.
  var state: PrayerState
  /// The listed day's known events, or `nil` when the day itself is unavailable.
  var day: PrayerDay?
  /// The listed day's kinds the source can't produce, in their order.
  var missingKinds: [PrayerKind]
  /// Why they're missing, or why the whole day is, when anything is.
  var missingReason: UnavailableReason?

  init(state: PrayerState, day availability: PrayerDayAvailability) {
    self.state = state
    switch availability {
    case .available(let day, .complete):
      self.day = day
      missingKinds = []
      missingReason = nil
    case .available(let day, .partial(let missing)):
      self.day = day
      missingKinds = missing.keys.sorted()
      missingReason = UnavailableReason(Array(missing.values))
    case .unavailable(let reason):
      day = nil
      missingKinds = PrayerKind.allCases
      missingReason = UnavailableReason([reason])
    }
  }

  /// Whether the schedule can't name the next prayer: the views show it as unknown, with no
  /// countdown.
  var nextIsUnknown: Bool { state.nextPrayer == nil }

  /// Whether anything is unknown: the next prayer or some of the day's times.
  var isPartial: Bool { nextIsUnknown || !missingKinds.isEmpty }
}

/// Why times are missing, in the app's own terms.
nonisolated enum UnavailableReason: Hashable, Sendable {
  /// The calculation can't produce the times here today, such as Isha in a polar summer.
  case cannotCalculate
  /// The place or settings are invalid, such as a latitude beyond the pole.
  case invalidInput
  /// The source has no data. A calculation always has data; a timetable may not.
  case noData

  /// The most telling reason among a gap's reasons: invalid input first, because nothing works
  /// until it's fixed, then a calculation that can't produce the times.
  init(_ reasons: [ScheduleGapReason]) {
    if reasons.contains(.invalidData) {
      self = .invalidInput
    } else if reasons.contains(.calculationUnavailable) {
      self = .cannotCalculate
    } else {
      self = .noData
    }
  }
}

/// The widget's wording for a display, in the chosen language.
nonisolated struct WidgetWording: Hashable, Sendable {
  /// The headline: "Choose a place", "Times need refreshing"; `nil` while times show.
  var title: String?
  /// The explanation, or the partial state's note; `nil` for a complete state.
  var message: String?
  /// A few words for the inline and circular Lock Screen widgets.
  var short: String?

  init(_ display: WidgetDisplay, strings: WidgetStrings, timeZone: TimeZone?) {
    switch display {
    case .setupRequired:
      title = strings("Choose a place")
      message = strings("Open PhoneWidgets to choose a place.")
      short = strings("Set up")
    case .unavailable(let reason):
      title = strings("No prayer times")
      message = Self.explanation(reason, strings: strings)
      short = Self.shortReason(reason, strings: strings)
    case .expired(let knownThrough):
      title = strings("Times need refreshing")
      let through = strings.dayAndTime(knownThrough, in: timeZone ?? .gmt)
      message = strings("Known until \(through). Open PhoneWidgets to refresh.")
      short = strings("Refresh")
    case .times(let times):
      title = nil
      short = times.nextIsUnknown ? strings("Unknown") : nil
      var notes: [String] = []
      if times.nextIsUnknown {
        notes.append(strings("The next prayer isn't known."))
      }
      if !times.missingKinds.isEmpty {
        let kinds = strings.list(times.missingKinds)
        switch times.missingReason {
        case .invalidInput?: notes.append(strings("\(kinds): invalid place or settings."))
        case .noData?: notes.append(strings("\(kinds): no times available."))
        case .cannotCalculate?, nil: notes.append(strings("\(kinds): can't be calculated today."))
        }
      }
      message = notes.isEmpty ? nil : notes.joined(separator: " ")
    }
  }

  private static func explanation(_ reason: UnavailableReason, strings: WidgetStrings) -> String {
    switch reason {
    case .cannotCalculate: strings("Prayer times can't be calculated here today.")
    case .invalidInput: strings("The place or the settings aren't valid.")
    case .noData: strings("No prayer times are available.")
    }
  }

  private static func shortReason(_ reason: UnavailableReason, strings: WidgetStrings) -> String {
    switch reason {
    case .cannotCalculate: strings("Can't calculate")
    case .invalidInput: strings("Invalid place")
    case .noData: strings("No times")
    }
  }
}
