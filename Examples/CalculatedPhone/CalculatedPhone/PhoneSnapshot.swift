import Foundation
import SalahCalculation
import SalahCore

/// Everything the main screen shows at one instant, as text in the app's language.
///
/// The view draws a snapshot and nothing else, so the app's logic is tested here without UI.
nonisolated struct PhoneSnapshot: Equatable, Sendable {
  /// The source facts used by SalahUI's list, alongside the screen's tested text snapshot.
  struct ListPresentation: Equatable, Sendable {
    var day: PrayerDay
    var state: PrayerState?
    var missing: [PrayerKind: ScheduleGapReason]
  }

  /// A prayer's status at the snapshot's instant (`PrayerState.status(of:)`).
  enum Status: Equatable, Sendable {
    case passed
    case justStarted
    case next(approaching: Bool)
    case upcoming
  }

  /// One expected kind of today, the civil day that contains the instant.
  struct Row: Equatable, Identifiable, Sendable {
    var kind: PrayerKind
    var name: String
    /// The time, or `nil` when the source can't give one.
    var time: String?
    /// "Next day" or "Previous evening" when the event's instant falls on another civil date
    /// than the day that owns it.
    var dayMarker: String?
    /// Why the time is missing, when it is: "Can't be calculated".
    var missing: String?
    /// `nil` when the state is unavailable, so the schedule can't say.
    var status: Status?
    var statusText: String?
    var id: String { kind.rawValue }
  }

  /// An event of the state: its name, time and, when another day owns it, that day.
  struct Moment: Equatable, Sendable {
    var name: String
    var time: String
    /// "Sunday's", when the event belongs to another day's schedule.
    var owningDay: String?
    /// "From Sunday's schedule", for VoiceOver.
    var owningDayLabel: String?
  }

  /// The next prayer, or why it can't be named.
  enum Next: Equatable, Sendable {
    case prayer(Moment, countdown: String, spokenCountdown: String)
    /// The state can't name the next prayer; `reason` names the gap that hides it, if any.
    case unknown(message: String, reason: String?)
  }

  /// Gaps in what the source can calculate, shown above the schedule.
  struct Banner: Equatable, Sendable {
    var title: String
    /// One line per gap: the day, the missing kinds and the reason.
    var gaps: [String]
  }

  var place: String
  var gregorianDate: String
  var hijriDate: String
  var clock: String
  var next: Next
  /// The latest prayer that started, if the state knows it.
  var latest: Moment?
  /// The latest event, when it isn't the latest prayer (sunrise).
  var previous: Moment?
  /// "Isha has started", inside the state's just-started window.
  var justStarted: String?
  var banner: Banner?
  /// Today's unavailability, when the source has nothing for it.
  var dayUnavailable: String?
  var rows: [Row]
  var list: ListPresentation
  var calculation: [ParameterRow]
  /// The next instant the state changes, within the look-ahead.
  var changesAt: Date?
}

extension PhoneSnapshot {
  /// The screen at an instant.
  static func make(settings: AppSettings, at now: Date, strings: PhoneStrings) -> PhoneSnapshot {
    let location = settings.place.location
    let format = PhoneFormat(strings: strings, timeZone: location.timeZone)
    let schedule = settings.schedule
    let today = CivilDay(containing: now, in: location.timeZone)
    // The state looks ahead to the end of tomorrow: far enough for the next Fajr after Isha.
    let state = schedule.state(at: now, through: today.adding(days: 2).start(in: location.timeZone))
    let prayerState = state.prayerState

    func moment(_ event: PrayerEvent) -> Moment {
      let other = event.scheduleDay != today
      let weekday = format.weekday(event.scheduleDay)
      return Moment(
        name: strings.names.name(of: event), time: format.time(event.time),
        owningDay: other ? strings("\(weekday)'s") : nil,
        owningDayLabel: other ? strings("From \(weekday)'s schedule") : nil)
    }

    func line(_ day: CivilDay, _ kinds: some Collection<PrayerKind>, _ reason: ScheduleGapReason)
      -> String
    {
      let names = format.list(kinds.sorted().map { strings.names.name(of: $0) })
      return strings("\(format.longDate(day)): \(names) (\(reason.sentence(strings)))")
    }

    var snapshot = PhoneSnapshot(
      place: placeName(settings.place, strings: strings),
      gregorianDate: format.longDate(now),
      hijriDate: HijriDateFormat(locale: strings.locale, timeZone: location.timeZone)
        .string(from: now),
      clock: format.clock(now),
      next: .unknown(message: "", reason: nil),
      rows: [],
      list: ListPresentation(
        day: PrayerDay(day: today, timeZone: location.timeZone, events: []),
        state: prayerState, missing: [:]),
      calculation: CalculationText(strings: strings).rows(settings),
      changesAt: state.changesAt)

    // Today's rows: a time, or the reason there is none. Never another day's time.
    let kinds = schedule.source.expectedKinds.sorted()
    var missingToday: [PrayerKind: ScheduleGapReason] = [:]
    switch schedule.day(today) {
    case .available(let day, let coverage):
      snapshot.list.day = day
      if case .partial(let missing) = coverage {
        missingToday = missing
      }
      for kind in kinds {
        if let event = day[kind] {
          let status = prayerState.map { Status($0.status(of: event)) }
          let civil = CivilDay(containing: event.time, in: location.timeZone)
          snapshot.rows.append(
            Row(
              kind: kind, name: strings.names.name(of: event), time: format.time(event.time),
              dayMarker: civil > day.day
                ? strings("Next day") : civil < day.day ? strings("Previous evening") : nil,
              status: status, statusText: status.map { $0.text(strings) } ?? strings("Unknown")))
        } else {
          missingToday[kind] = missingToday[kind] ?? .calculationUnavailable
          snapshot.rows.append(
            Row(
              kind: kind, name: strings.names.name(of: kind),
              missing: (missingToday[kind] ?? .calculationUnavailable).label(strings)))
        }
      }
    case .unavailable(let reason):
      for kind in kinds {
        missingToday[kind] = reason
        snapshot.rows.append(
          Row(kind: kind, name: strings.names.name(of: kind), missing: reason.label(strings)))
      }
      snapshot.dayUnavailable = strings("Today's times can't be shown: \(reason.sentence(strings))")
    }
    snapshot.list.missing = missingToday

    // The state: the next prayer, the latest one, and what hides them.
    let prayerGaps = state.coverage.gaps
      .filter { $0.kinds.contains(where: \.isPrayer) && $0.interval.end > now }
    let firstGap = prayerGaps.first.map { line($0.day, $0.kinds, $0.reason) }
    switch state {
    case .available(let prayerState, _):
      if let next = prayerState.nextPrayer {
        let remaining = next.time.timeIntervalSince(now)
        snapshot.next = .prayer(
          moment(next),
          countdown: PrayerDurationFormat.string(remaining, locale: strings.locale),
          spokenCountdown: PrayerDurationFormat.string(
            remaining, width: .spoken, locale: strings.locale))
      } else if let firstGap {
        snapshot.next = .unknown(
          message: strings("The next prayer can't be named."), reason: firstGap)
      } else {
        snapshot.next = .unknown(
          message: strings("No prayer is known before the end of tomorrow."), reason: nil)
      }
      snapshot.latest = prayerState.latestPrayer.map(moment)
      if let previous = prayerState.previous, previous != prayerState.latestPrayer {
        snapshot.previous = moment(previous)
      }
      if let started = prayerState.justStarted {
        snapshot.justStarted = strings("\(strings.names.name(of: started)) has started")
      }
    case .unavailable(let coverage, _):
      snapshot.next = .unknown(
        message: strings("The next prayer can't be named."), reason: firstGap)
      snapshot.banner = Banner(
        title: strings("No current or next prayer can be named"),
        gaps: relevantGaps(coverage.gaps, at: now).map { line($0.day, $0.kinds, $0.reason) })
    }

    // A day with missing kinds explains them, unless the state's banner already does.
    if snapshot.banner == nil, !missingToday.isEmpty {
      let reasons = Set(missingToday.values).sorted { $0.order < $1.order }
      snapshot.banner = Banner(
        title: missingToday.count == kinds.count
          ? strings("Today's times can't be shown") : strings("Some of today's times are missing"),
        gaps: reasons.map { reason in
          line(today, missingToday.filter { $0.value == reason }.keys, reason)
        })
    }
    return snapshot
  }

  /// The gaps to explain: those at `now` first, then the rest, at most three.
  static func relevantGaps(_ gaps: [ScheduleGap], at now: Date) -> [ScheduleGap] {
    let current = gaps.filter { $0.interval.start <= now && now < $0.interval.end }
    let later = gaps.filter { !current.contains($0) }
    return Array((current + later).prefix(3))
  }

  /// The place's name in the app's language.
  static func placeName(_ place: Place, strings: PhoneStrings) -> String {
    switch place.id {
    case Place.makkah.id: strings("Makkah")
    case Place.london.id: strings("London")
    case Place.kashgar.id: strings("Kashgar")
    case Place.kazan.id: strings("Kazan")
    case Place.tromso.id: strings("Tromsø")
    case Place.invalid.id: strings("Invalid coordinates")
    default: place.location.name ?? strings("Custom location")
    }
  }
}

extension PhoneSnapshot.Status {
  init(_ status: PrayerEventStatus) {
    switch status {
    case .passed: self = .passed
    case .justStarted: self = .justStarted
    case .next(let approaching): self = .next(approaching: approaching)
    case .upcoming: self = .upcoming
    }
  }

  func text(_ strings: PhoneStrings) -> String {
    switch self {
    case .passed: strings("Passed")
    case .justStarted: strings("Started")
    case .next(approaching: false): strings("Next")
    case .next(approaching: true): strings("Next, soon")
    case .upcoming: strings("Upcoming")
    }
  }
}

extension ScheduleGapReason {
  /// The reason inside a sentence: "can't be calculated".
  nonisolated func sentence(_ strings: PhoneStrings) -> String {
    switch self {
    case .calculationUnavailable: strings("can't be calculated")
    case .invalidData: strings("invalid location or settings")
    case .noPublishedData: strings("not published")
    case .unresolvedWallTime: strings("the local time is skipped or repeated")
    }
  }

  /// The reason in place of a time: "Can't be calculated".
  nonisolated func label(_ strings: PhoneStrings) -> String {
    switch self {
    case .calculationUnavailable: strings("Can't be calculated")
    case .invalidData: strings("Invalid location or settings")
    case .noPublishedData: strings("Not published")
    case .unresolvedWallTime: strings("The local time is skipped or repeated")
    }
  }

  /// SalahCore's declaration order, which coverage uses to sort gaps.
  nonisolated var order: Int {
    switch self {
    case .noPublishedData: 0
    case .calculationUnavailable: 1
    case .invalidData: 2
    case .unresolvedWallTime: 3
    }
  }
}
