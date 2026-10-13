import Foundation
import SalahCore
import SalahTimes

/// A prayer source that calculates every day with SalahTimes.
///
/// ```swift
/// let source = CalculationSource(CalculationSettings(method: .ummAlQura))
/// let schedule = PrayerSchedule(source: source, location: location)
/// ```
///
/// For each owning day, the source computes the six kinds with ``settings``, in the location's
/// time zone, and reports what SalahCore's source contract can hold. It never invents, moves or
/// reorders a time:
/// - A kind that doesn't occur, such as Isha when the Sun never gets 18° below the horizon with
///   `HighLatitudeRule.disabled`, or sunset during polar day, is missing with
///   `ScheduleGapReason.calculationUnavailable`.
/// - So is a time the contract can't place: one earlier than ``maximumLead`` before the start of
///   its day or not before the start of the day after the next, one that isn't strictly after
///   the kind before it (the later kind of an equal or inverted pair is missing, such as an Isha
///   that a high-latitude bound puts at Maghrib's instant), and one after an event of a later
///   day (such as an interval Isha after the next Fajr near the polar circles).
/// - A day with nothing left is unavailable with `ScheduleGapReason.calculationUnavailable`,
///   and so is a date its time zone skips. Otherwise a day SalahTimes refuses is unavailable
///   for the first problem it finds, in this order: coordinates it rejects
///   (`ScheduleGapReason.invalidData`), a year outside the range it calculates
///   (`ScheduleGapReason.calculationUnavailable`), then parameters it rejects
///   (`ScheduleGapReason.invalidData`).
///
/// An event belongs to the day it was computed for, even when it occurs on a neighboring civil
/// date: Isha after midnight belongs to the evening before, and where the clock runs behind the
/// Sun, a Fajr just before midnight belongs to the next day.
///
/// The source declares no Jumu'ah and no iqama. A Friday's Dhuhr is ordinary unless your app
/// declares Jumu'ah in a source that wraps this one, and a mosque's congregation times come from
/// `IqamaRules`.
nonisolated public struct CalculationSource: PrayerSource, Hashable, Sendable {
  /// How the source calculates.
  public let settings: CalculationSettings

  /// Creates a source that calculates with these settings.
  ///
  /// - Parameter settings: The calculation settings, passed to SalahTimes unchanged.
  public init(_ settings: CalculationSettings) {
    self.settings = settings
  }

  /// All six kinds: Fajr, sunrise, Dhuhr, Asr, Maghrib and Isha.
  public var expectedKinds: Set<PrayerKind> { Self.kinds }

  /// Twelve hours, the most SalahCore allows.
  ///
  /// Where the clock runs behind the Sun, a Fajr near the middle of the night falls shortly
  /// before its day begins: in Kazan, under the middle-of-the-night rule, between 23:40 and
  /// 23:52 on the evening before, from May to August. Near the polar circles, sunrise can too.
  public var maximumLead: Duration { .seconds(Self.leadSeconds) }

  /// The calculated events of `day` at `location`, or why there are none.
  ///
  /// - Parameters:
  ///   - day: The owning day, a civil date in the location's time zone.
  ///   - location: Where to calculate. Its time zone defines the day.
  /// - Returns: The day's events and coverage, or the reason it's unavailable.
  public func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    guard day.isValid else { return .unavailable(.invalidData) }
    var calculated: Calculated
    switch calculate(day, at: location) {
    case .success(let value): calculated = value
    case .failure(let unavailable): return .unavailable(unavailable.reason)
    }

    // No event of a day may follow an event of a later day; the earlier day gives way.
    if let latest = calculated.times.values.max(),
      let first = earliestLaterTime(after: day, before: latest, at: location)
    {
      for (kind, time) in calculated.times where time > first {
        calculated.times[kind] = nil
        calculated.missing[kind] = .calculationUnavailable
      }
    }

    guard !calculated.times.isEmpty else { return .unavailable(.calculationUnavailable) }
    let events = calculated.times.map {
      PrayerEvent(scheduleDay: day, kind: $0.key, time: $0.value)
    }
    return .available(
      PrayerDay(day: day, timeZone: location.timeZone, events: events),
      coverage: calculated.missing.isEmpty ? .complete : .partial(missing: calculated.missing))
  }

  // MARK: - Calculating one day

  private static let kinds = Set(PrayerKind.allCases)
  private static let leadSeconds: TimeInterval = 12 * 3_600

  /// One day's times that the contract can hold, and the kinds it can't.
  private struct Calculated {
    var times: [PrayerKind: Date]
    var missing: [PrayerKind: ScheduleGapReason]
  }

  private struct Unavailable: Error {
    var reason: ScheduleGapReason
  }

  /// The earliest time calculated for a day after `day` that could come before `latest`, the
  /// latest time of `day`.
  ///
  /// A later day's times start at most 12 hours before it begins, so only the days that begin
  /// less than 12 hours after `latest` count: normally the next day, and the one after it when
  /// `latest` is late on the next day. That way a later day without events, such as a date its
  /// zone skips, doesn't hide the day after it.
  private func earliestLaterTime(
    after day: CivilDay, before latest: Date, at location: PrayerLocation
  ) -> Date? {
    var earliest: Date?
    var later = day.adding(days: 1)
    while later.start(in: location.timeZone).addingTimeInterval(-Self.leadSeconds) < latest {
      if case .success(let calculated) = calculate(later, at: location),
        let first = calculated.times.values.min()
      {
        earliest = min(earliest ?? first, first)
      }
      later = later.adding(days: 1)
    }
    return earliest
  }

  /// The times SalahTimes computes for `day`, without the ones outside the day's span or out
  /// of order. The check against later days is the caller's.
  private func calculate(
    _ day: CivilDay, at location: PrayerLocation
  ) -> Result<Calculated, Unavailable> {
    let zone = location.timeZone
    let start = day.start(in: zone)
    // A date its zone skips, such as Pacific/Apia's 2011-12-30, has no time on the clock.
    guard day.adding(days: 1).start(in: zone) > start,
      let gregorian = GregorianDay(year: day.year, month: day.month, day: day.day)
    else { return .failure(Unavailable(reason: .calculationUnavailable)) }

    let times: PrayerTimes
    do {
      times = try PrayerTimes(
        coordinates: Coordinates(latitude: location.latitude, longitude: location.longitude),
        day: gregorian, timeZone: zone, parameters: settings.parameters)
    } catch CalculationError.unsupportedDate {
      return .failure(Unavailable(reason: .calculationUnavailable))
    } catch {
      return .failure(Unavailable(reason: .invalidData))
    }

    let earliest = start.addingTimeInterval(-Self.leadSeconds)
    let end = day.adding(days: 2).start(in: zone)
    var calculated = Calculated(times: [:], missing: [:])
    var latest: Date?
    for kind in PrayerKind.allCases {
      guard let time = times[Self.event(of: kind)].date, time >= earliest, time < end,
        latest.map({ time > $0 }) ?? true
      else {
        calculated.missing[kind] = .calculationUnavailable
        continue
      }
      calculated.times[kind] = time
      latest = time
    }
    return .success(calculated)
  }

  private static func event(of kind: PrayerKind) -> PrayerTimes.Event {
    switch kind {
    case .fajr: .fajr
    case .sunrise: .sunrise
    case .dhuhr: .dhuhr
    case .asr: .asr
    case .maghrib: .maghrib
    case .isha: .isha
    }
  }
}
