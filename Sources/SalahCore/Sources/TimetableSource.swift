import Foundation

/// Published prayer times: a mosque's timetable, a ministry's yearly table, a CSV or JSON file.
///
/// A timetable holds one ``Row`` per owning day, with times as the publisher prints them:
/// local wall-clock times, resolved in the location's time zone when a day is asked for, or
/// instants the publisher already resolved. It never fills a missing day or time from another
/// one.
///
/// The initializer doesn't throw. A row that breaks the rules below makes only its own day
/// ``PrayerDayAvailability/unavailable(_:)`` with ``ScheduleGapReason/invalidData``, so a yearly
/// table with one typo still serves its other days:
/// - no other row has the same day;
/// - every kind in `times` is in ``expectedKinds``;
/// - every kind in `iqama` is a prayer (not sunrise) that has a time in the row;
/// - every kind in `observances` has a time in the row, and ``PrayerObservance/jumuah`` appears
///   only on the Dhuhr of a Friday;
/// - every wall time has an hour from 0 to 23, a minute from 0 to 59 and a day offset of 0 or 1.
///
/// When a day is asked for, a time that its ``wallTimeResolution`` can't resolve leaves its
/// kind missing with ``ScheduleGapReason/unresolvedWallTime``. Resolved times must lie between
/// the start of the owning day and the start of the day after the next, and strictly increase
/// in canonical kind order; otherwise the day is invalid. An iqama that doesn't resolve, comes
/// before its prayer or falls after that span is dropped, without affecting coverage.
///
/// `TimetableSource` is `Codable` in this shape:
///
/// ```json
/// {
///   "expectedKinds": ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"],
///   "wallTimeResolution": { "repeated": "reject", "nonexistent": "reject" },
///   "rows": [
///     {
///       "day": "2026-10-16",
///       "times": { "fajr": "05:31", "sunrise": "07:24", "dhuhr": "12:52",
///                  "asr": "15:37", "maghrib": "18:08", "isha": "19:41" },
///       "iqama": { "fajr": "06:00", "dhuhr": "13:30" },
///       "observances": { "dhuhr": "jumuah" }
///     }
///   ]
/// }
/// ```
///
/// `wallTimeResolution`, `iqama` and `observances` are optional.
nonisolated public struct TimetableSource: PrayerSource, Codable, Hashable, Sendable {
  /// One owning day's published times.
  public struct Row: Codable, Hashable, Sendable {
    /// The owning day.
    public var day: CivilDay
    /// The begin time of each published kind. A kind the publisher left out is missing.
    public var times: [PrayerKind: TimetableTime]
    /// Published congregation times, by prayer.
    public var iqama: [PrayerKind: TimetableTime]
    /// Declared observances, by kind; Jumu'ah only when the publisher declares it.
    public var observances: [PrayerKind: PrayerObservance]

    /// Creates a row.
    public init(
      day: CivilDay, times: [PrayerKind: TimetableTime],
      iqama: [PrayerKind: TimetableTime] = [:],
      observances: [PrayerKind: PrayerObservance] = [:]
    ) {
      self.day = day
      self.times = times
      self.iqama = iqama
      self.observances = observances
    }

    private enum CodingKeys: String, CodingKey {
      case day, times, iqama, observances
    }

    /// Decodes a row; `iqama` and `observances` are optional.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        day: try container.decode(CivilDay.self, forKey: .day),
        times: try container.decodeIfPresent([PrayerKind: TimetableTime].self, forKey: .times)
          ?? [:],
        iqama: try container.decodeIfPresent([PrayerKind: TimetableTime].self, forKey: .iqama)
          ?? [:],
        observances: try container.decodeIfPresent(
          [PrayerKind: PrayerObservance].self, forKey: .observances) ?? [:])
    }

    /// Encodes the row, leaving out empty `iqama` and `observances`.
    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(day, forKey: .day)
      try container.encode(times, forKey: .times)
      if !iqama.isEmpty { try container.encode(iqama, forKey: .iqama) }
      if !observances.isEmpty { try container.encode(observances, forKey: .observances) }
    }
  }

  /// The kinds this timetable publishes; leave out sunrise for a five-prayer table.
  public let expectedKinds: Set<PrayerKind>
  /// The rows, sorted by day.
  public let rows: [Row]
  /// How to read local times that a clock change makes repeated or nonexistent.
  public let wallTimeResolution: WallTimeResolution

  /// Creates a timetable. Rows may come in any order; a bad row affects only its own day.
  public init(
    rows: [Row], expectedKinds: Set<PrayerKind>,
    wallTimeResolution: WallTimeResolution = WallTimeResolution()
  ) {
    self.rows = rows.enumerated()
      .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
      .map(\.element)
    self.expectedKinds = expectedKinds
    self.wallTimeResolution = wallTimeResolution
  }

  /// The day of the earliest row, if there is one.
  public var firstDay: CivilDay? { rows.first?.day }

  /// The day of the latest row, if there is one.
  public var lastDay: CivilDay? { rows.last?.day }

  /// The published events of `day`, resolved in the location's time zone.
  public func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    guard day.isValid, !expectedKinds.isEmpty else { return .unavailable(.invalidData) }
    let matches = rows(on: day)
    guard let row = matches.first else { return .unavailable(.noPublishedData) }
    guard matches.count == 1 else { return .unavailable(.invalidData) }
    guard !row.times.isEmpty else { return .unavailable(.noPublishedData) }
    guard passesChecks(row) else { return .unavailable(.invalidData) }

    let zone = location.timeZone
    let spanStart = day.start(in: zone)
    let spanEnd = day.adding(days: 2).start(in: zone)
    var times: [PrayerKind: Date] = [:]
    var missing: [PrayerKind: ScheduleGapReason] = [:]
    for kind in expectedKinds {
      guard let time = row.times[kind] else {
        missing[kind] = .noPublishedData
        continue
      }
      if let instant = resolve(time, on: day, in: zone) {
        times[kind] = instant
      } else {
        missing[kind] = .unresolvedWallTime
      }
    }

    let ordered = times.sorted { $0.key < $1.key }
    for (index, entry) in ordered.enumerated() {
      guard entry.value >= spanStart, entry.value < spanEnd else {
        return .unavailable(.invalidData)
      }
      if index > 0, ordered[index - 1].value >= entry.value {
        return .unavailable(.invalidData)
      }
    }
    guard !ordered.isEmpty else { return .unavailable(.unresolvedWallTime) }

    let events = ordered.map { kind, time in
      var iqama: Date?
      if let published = row.iqama[kind], let instant = resolve(published, on: day, in: zone),
        instant >= time, instant < spanEnd
      {
        iqama = instant
      }
      return PrayerEvent(
        scheduleDay: day, kind: kind, time: time, iqama: iqama,
        observance: row.observances[kind] ?? .ordinary)
    }
    return .available(
      PrayerDay(day: day, timeZone: zone, events: events),
      coverage: missing.isEmpty ? .complete : .partial(missing: missing))
  }

  /// The rows whose day is `day`; more than one makes the day invalid.
  private func rows(on day: CivilDay) -> ArraySlice<Row> {
    var low = 0
    var high = rows.count
    while low < high {
      let middle = (low + high) / 2
      if rows[middle].day < day { low = middle + 1 } else { high = middle }
    }
    var end = low
    while end < rows.count, rows[end].day == day { end += 1 }
    return rows[low..<end]
  }

  private func passesChecks(_ row: Row) -> Bool {
    guard row.times.keys.allSatisfy(expectedKinds.contains) else { return false }
    guard row.iqama.keys.allSatisfy({ $0.isPrayer && row.times[$0] != nil }) else { return false }
    for (kind, observance) in row.observances {
      guard row.times[kind] != nil else { return false }
      if observance == .jumuah, kind != .dhuhr || row.day.weekday != 6 { return false }
    }
    return (Array(row.times.values) + Array(row.iqama.values)).allSatisfy { time in
      if case .local(let wallTime) = time { return wallTime.isValid }
      return true
    }
  }

  private func resolve(_ time: TimetableTime, on day: CivilDay, in zone: TimeZone) -> Date? {
    switch time {
    case .instant(let date): date
    case .local(let wallTime):
      WallTimeResolver.instant(of: wallTime, on: day, in: zone, policy: wallTimeResolution)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case expectedKinds, wallTimeResolution, rows
  }

  /// Decodes a timetable; `wallTimeResolution` is optional.
  ///
  /// Decoding fails only for malformed values. Content that breaks the rules above decodes,
  /// and makes its day invalid.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rows: try container.decode([Row].self, forKey: .rows),
      expectedKinds: Set(try container.decode([PrayerKind].self, forKey: .expectedKinds)),
      wallTimeResolution: try container.decodeIfPresent(
        WallTimeResolution.self, forKey: .wallTimeResolution) ?? WallTimeResolution())
  }

  /// Encodes the timetable with `expectedKinds` in canonical order.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(expectedKinds.sorted(), forKey: .expectedKinds)
    try container.encode(wallTimeResolution, forKey: .wallTimeResolution)
    try container.encode(rows, forKey: .rows)
  }
}
