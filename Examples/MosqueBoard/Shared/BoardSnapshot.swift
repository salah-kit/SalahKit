import Foundation
import SalahCore

/// Everything the board shows at one instant, as text in the board's language.
///
/// The view draws a snapshot and nothing else, so the board's logic is tested here without UI.
nonisolated struct BoardSnapshot: Equatable, Sendable {
  /// A prayer's status at the snapshot's instant (`PrayerState.status(of:)`).
  enum Status: Equatable, Sendable {
    case passed
    case justStarted
    case next(approaching: Bool)
    case upcoming
  }

  /// One expected kind of the shown day.
  struct Row: Equatable, Identifiable, Sendable {
    var kind: PrayerKind
    /// "Jumuah" only when the event declares it.
    var name: String
    /// The begin time, or `nil` when the timetable doesn't publish it.
    var time: String?
    /// Whether the time is on the next calendar day (written `+1` in the timetable).
    var isNextDay: Bool
    var iqama: String?
    /// Whether the iqama falls on the calendar day after the begin time: Isha at 23:54 with
    /// its iqama at 00:05.
    var iqamaIsNextDay = false
    /// Why the time is missing, when it is.
    var missingReason: String?
    /// `nil` when the state is unavailable, so the schedule can't say.
    var status: Status?
    var statusText: String?
    var id: String { kind.rawValue }

    /// The text shown in place of a missing time: its reason, starting with a capital.
    var missingText: String? {
      missingReason.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
  }

  /// The next prayer, or why there isn't one.
  enum Next: Equatable, Sendable {
    /// The next prayer is known.
    case prayer(
      name: String, time: String, countdown: String, spokenCountdown: String,
      owningDay: String?)
    /// The state is known, but the timetable publishes nothing after the latest prayer.
    case unpublished(String)
  }

  /// Why the board can't name the current or next prayer.
  struct Banner: Equatable, Sendable {
    var title: String
    /// One line per gap: the day, the missing kinds and the reason.
    var gaps: [String]
  }

  var title: String
  var subtitle: String
  var gregorianDate: String
  var hijriDate: String
  var clock: String
  /// The shown day's unavailability, when it has no events.
  var dayUnavailable: String?
  var rows: [Row]
  var justStarted: String?
  var next: Next?
  var banner: Banner?
  var policy: String
  var attribution: String?
  /// The next instant the state changes, within the look-ahead.
  var changesAt: Date?
}

extension BoardSnapshot {
  /// How far ahead the state looks for the next prayer.
  static let lookAhead: TimeInterval = 2 * 86_400

  /// The board at an instant.
  static func make(board: Board, at now: Date, strings: BoardStrings) -> BoardSnapshot {
    let format = BoardFormat(strings: strings, timeZone: board.location.timeZone)
    let schedule = board.schedule
    let today = CivilDay(containing: now, in: format.timeZone)
    let state = schedule.state(at: now, through: now.addingTimeInterval(lookAhead))
    let prayerState = state.prayerState

    var snapshot = BoardSnapshot(
      title: title(of: board.id, strings: strings),
      subtitle: subtitle(of: board.id, strings: strings),
      gregorianDate: format.longDate(now),
      hijriDate: HijriDateFormat(locale: strings.locale, timeZone: format.timeZone)
        .string(from: now),
      clock: format.time(now),
      rows: [],
      policy: policy(of: board.id, strings: strings),
      attribution: board.id == .muis ? muisAttribution : nil,
      changesAt: state.changesAt)

    switch schedule.day(containing: now) {
    case .available(let day, let coverage):
      let missing: [PrayerKind: ScheduleGapReason] =
        switch coverage {
        case .complete: [:]
        case .partial(let missing): missing
        }
      for kind in schedule.source.expectedKinds.sorted() {
        if let event = day[kind] {
          let status = prayerState.map { Status($0.status(of: event)) }
          snapshot.rows.append(
            Row(
              kind: kind, name: strings.names.name(of: event), time: format.time(event.time),
              isNextDay: CivilDay(containing: event.time, in: format.timeZone) != today,
              iqama: event.iqama.map(format.time),
              iqamaIsNextDay: event.iqama.map {
                CivilDay(containing: $0, in: format.timeZone)
                  != CivilDay(containing: event.time, in: format.timeZone)
              } ?? false,
              missingReason: nil, status: status,
              statusText: status.map { $0.text(strings) } ?? strings("Unknown")))
        } else {
          let reason = missing[kind] ?? .noPublishedData
          snapshot.rows.append(
            Row(
              kind: kind, name: strings.names.name(of: kind), time: nil, isNextDay: false,
              iqama: nil, missingReason: reason.text(strings), status: nil, statusText: nil))
        }
      }
    case .unavailable(.noPublishedData):
      snapshot.dayUnavailable = strings("The timetable publishes no times for this day.")
    case .unavailable(let reason):
      snapshot.dayUnavailable = strings("This day's times can't be shown: \(reason.text(strings))")
    }

    switch state {
    case .available(let prayerState, _):
      if let started = prayerState.justStarted {
        snapshot.justStarted = strings("\(strings.names.name(of: started)) has started")
      }
      if let next = prayerState.nextPrayer {
        let remaining = next.time.timeIntervalSince(now)
        snapshot.next = .prayer(
          name: strings.names.name(of: next),
          time: format.time(next.time),
          countdown: PrayerDurationFormat.string(remaining, locale: strings.locale),
          spokenCountdown: PrayerDurationFormat.string(
            remaining, width: .spoken, locale: strings.locale),
          owningDay: next.scheduleDay == today
            ? nil
            : strings("From the timetable of \(format.longDate(next.scheduleDay))"))
      } else {
        snapshot.next = .unpublished(strings("The next prayer isn't published yet"))
      }
    case .unavailable(let coverage, _):
      snapshot.banner = Banner(
        title: strings("The timetable doesn't cover this time"),
        gaps: relevantGaps(coverage.gaps, at: now).map { gap in
          let kinds = gap.kinds.sorted().map { strings.names.name(of: $0) }
            .formatted(.list(type: .and).locale(strings.locale))
          return strings(
            "\(format.longDate(gap.day)): \(kinds) (\(gap.reason.text(strings)))")
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

  /// The attribution SODL v1.0 requires, kept verbatim in every language.
  static let muisAttribution =
    "Contains information from Muslim Prayer Timetable 2026 accessed on 2026-10-13 from "
    + "data.gov.sg (Majlis Ugama Islam Singapura) which is made available under the terms of "
    + "the Singapore Open Data Licence version 1.0 https://data.gov.sg/open-data-licence"

  private static func title(of id: Board.ID, strings: BoardStrings) -> String {
    switch id {
    case .muis: strings("Singapore")
    case .edinburgh: strings("Edinburgh Example Mosque")
    }
  }

  private static func subtitle(of id: Board.ID, strings: BoardStrings) -> String {
    switch id {
    case .muis: strings("MUIS Muslim Prayer Timetable 2026")
    case .edinburgh: strings("Synthetic timetable for a fictional mosque")
    }
  }

  private static func policy(of id: Board.ID, strings: BoardStrings) -> String {
    switch id {
    case .muis:
      strings(
        "Iqama times and Friday Jumuah are this app's own settings, not part of the MUIS timetable."
      )
    case .edinburgh:
      strings("Begin times, iqama and Jumuah all come from this synthetic timetable.")
    }
  }
}

extension BoardSnapshot.Status {
  init(_ status: PrayerEventStatus) {
    switch status {
    case .passed: self = .passed
    case .justStarted: self = .justStarted
    case .next(let approaching): self = .next(approaching: approaching)
    case .upcoming: self = .upcoming
    }
  }

  func text(_ strings: BoardStrings) -> String {
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
  nonisolated func text(_ strings: BoardStrings) -> String {
    switch self {
    case .noPublishedData: strings("not published")
    case .calculationUnavailable: strings("can't be calculated")
    case .invalidData: strings("invalid data")
    case .unresolvedWallTime: strings("the local time is skipped or repeated")
    }
  }
}

/// Dates and times in the board's zone and language.
nonisolated struct BoardFormat: Sendable {
  let locale: Locale
  let timeZone: TimeZone
  private let calendar: Calendar

  init(strings: BoardStrings, timeZone: TimeZone) {
    locale = strings.locale
    self.timeZone = timeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = strings.locale
    self.calendar = calendar
  }

  /// A 24-hour clock time with the locale's digits, as mosque timetables print it: "05:31".
  func time(_ date: Date) -> String {
    date.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        locale: locale, timeZone: timeZone, calendar: calendar))
  }

  /// "Wednesday, 14 October 2026" in the board's language.
  func longDate(_ date: Date) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone))
  }

  /// A calendar day, formatted from its start in the board's zone.
  func longDate(_ day: CivilDay) -> String {
    longDate(day.start(in: timeZone))
  }
}
