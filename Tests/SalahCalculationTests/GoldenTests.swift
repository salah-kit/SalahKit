import Foundation
import SalahCalculation
import SalahTimes
import Testing

@testable import SalahCore

/// Runs SalahTimes' own prayer-time vectors (`Tests/Data/SalahTimes-0.1.0/times`) through
/// `CalculationSource` (RFC 0002, section 7).
///
/// Every time SalahTimes expects comes out of the source unchanged, within the vectors' own
/// tolerance, or its kind is missing with `.calculationUnavailable` for a reason of RFC 0002,
/// section 4.5 that the vector's data shows: the event doesn't occur, it lies outside
/// `[start(D) − 12 h, start(D + 2))`, it isn't strictly after the kind kept before it, or it is
/// after the next day's first event. The next day is calculated with SalahTimes directly.
@Suite struct GoldenTests {
  @Test(arguments: GoldenVectors.fileNames)
  func file(_ name: String) {
    let vectors = GoldenVectors.catalog.vectors.filter { $0.file == name }
    #expect(!vectors.isEmpty, "\(name) has no vectors")
    for vector in vectors {
      _ = GoldenVectors.check(vector)
    }
  }

  @Test func everyFileLoads() {
    let catalog = GoldenVectors.catalog
    #expect(catalog.problems.isEmpty, "\(catalog.problems)")
    #expect(Set(catalog.vectors.map(\.file)) == Set(GoldenVectors.fileNames))
    // SalahTimes 0.1.0 has 1196 prayer-time vectors (its Vectors/README.md).
    #expect(catalog.vectors.count == 1196)
    let ids = catalog.vectors.map(\.id)
    #expect(Set(ids).count == ids.count, "vector ids are unique")
  }

  /// Counts what the adapter did with SalahTimes' vectors, and checks every count adds up.
  @Test func summary() {
    var summary = GoldenSummary()
    for vector in GoldenVectors.catalog.vectors {
      summary.add(GoldenVectors.check(vector, recordIssues: false), id: vector.id)
    }
    #expect(summary.days == GoldenVectors.catalog.vectors.count)
    #expect(summary.complete + summary.partial + summary.unavailable == summary.days)
    #expect(summary.complete > 0 && summary.partial > 0)
    print(summary)
  }
}

/// What the adapter did with one vector.
nonisolated struct GoldenOutcome: Sendable {
  enum Availability: Sendable { case complete, partial, unavailable }
  var availability: Availability
  /// For each missing kind, the first justification that holds.
  var missing: [PrayerKind: GoldenVectors.Justification]
}

nonisolated struct GoldenSummary: CustomStringConvertible {
  var days = 0
  var complete = 0
  var partial = 0
  var unavailable = 0
  var missing: [GoldenVectors.Justification: Int] = [:]
  /// The vectors with a kind missing for a reason other than non-occurrence.
  var rare: [String] = []

  mutating func add(_ outcome: GoldenOutcome, id: String) {
    days += 1
    switch outcome.availability {
    case .complete: complete += 1
    case .partial: partial += 1
    case .unavailable: unavailable += 1
    }
    for (kind, justification) in outcome.missing.sorted(by: { $0.key < $1.key }) {
      missing[justification, default: 0] += 1
      if justification != .doesNotOccur {
        rare.append("\(id) \(kind): \(justification.rawValue)")
      }
    }
  }

  var description: String {
    let kinds = missing.sorted { $0.key.rawValue < $1.key.rawValue }
      .map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")
    return
      "SalahTimes 0.1.0 vectors through CalculationSource: \(days) days, \(complete) complete, "
      + "\(partial) partial, \(unavailable) unavailable; missing kinds by reason: \(kinds)\n"
      + rare.map { "  \($0)" }.joined(separator: "\n")
  }
}

nonisolated enum GoldenVectors {
  /// One prayer-time vector of SalahTimes, resolved to the types the adapter takes.
  struct Vector: Sendable {
    var file: String
    var id: String
    var day: CivilDay
    var location: PrayerLocation
    var parameters: CalculationParameters
    var expected: [PrayerKind: EventTime]
    var tolerance: TimeInterval
  }

  /// Why a kind is missing, in the order `check` tries them (RFC 0002, section 4.5).
  enum Justification: String, Sendable {
    case doesNotOccur
    case outsideOwningSpan
    case notAfterPreviousKind
    case afterNextDaysFirstEvent
    case skippedDate
  }

  struct Catalog: Sendable {
    var vectors: [Vector] = []
    var problems: [String] = []
  }

  static let lead: TimeInterval = 12 * 3_600

  static let fileNames = [
    "adjustments-rounding.json", "custom.json", "date-line-equator.json", "dst.json",
    "high-latitude.json", "isha-after-midnight.json", "madhab.json", "methods.json",
    "polar.json", "ramadan.json", "ranges.json",
  ]

  /// `Tests/Data/SalahTimes-0.1.0`, found from this file's path.
  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data").appendingPathComponent("SalahTimes-0.1.0")

  static let catalog: Catalog = load()

  // MARK: Checking

  /// Checks one vector and returns what the adapter did with it.
  @discardableResult
  static func check(_ vector: Vector, recordIssues: Bool = true) -> GoldenOutcome {
    func issue(_ text: String) {
      if recordIssues { Issue.record("\(vector.id): \(text)") }
    }
    let zone = vector.location.timeZone
    let source = CalculationSource(CalculationSettings(parameters: vector.parameters))
    let answer = source.prayerDay(vector.day, at: vector.location)
    let justifications = missingJustifications(vector)

    switch answer {
    case .unavailable(let reason):
      if reason != .calculationUnavailable {
        issue("unavailable(\(reason)) for valid input")
      }
      let skipped = vector.day.adding(days: 1).start(in: zone) <= vector.day.start(in: zone)
      if skipped {
        return GoldenOutcome(
          availability: .unavailable,
          missing: Dictionary(uniqueKeysWithValues: PrayerKind.allCases.map { ($0, .skippedDate) }))
      }
      var missing: [PrayerKind: Justification] = [:]
      for kind in PrayerKind.allCases {
        if let justification = justifications[kind] {
          missing[kind] = justification
        } else {
          issue("the day is unavailable, but \(kind) isn't justified missing")
        }
      }
      return GoldenOutcome(availability: .unavailable, missing: missing)

    case .available(let day, let coverage):
      var missingReasons: [PrayerKind: ScheduleGapReason] = [:]
      if case .partial(let reasons) = coverage { missingReasons = reasons }
      var missing: [PrayerKind: Justification] = [:]
      for kind in PrayerKind.allCases {
        guard let expected = vector.expected[kind] else {
          issue("\(kind) has no expectation")
          continue
        }
        if let event = day[kind] {
          #expect(missingReasons[kind] == nil, "\(vector.id): \(kind) both present and missing")
          guard let want = expected.date else {
            issue("\(kind) is present, but SalahTimes expects \(expected)")
            continue
          }
          let difference = event.time.timeIntervalSince(want)
          if abs(difference) > vector.tolerance {
            issue("\(kind): expected \(want), got \(event.time) (\(difference) s)")
          }
        } else {
          if missingReasons[kind] != .calculationUnavailable {
            issue("\(kind) is missing with \(String(describing: missingReasons[kind]))")
          }
          if let justification = justifications[kind] {
            missing[kind] = justification
          } else {
            issue("\(kind) is missing, but the vector's data doesn't justify it (\(expected))")
          }
        }
      }
      return GoldenOutcome(availability: missing.isEmpty ? .complete : .partial, missing: missing)
    }
  }

  /// For each kind the vector's data allows to be missing, the first reason that applies.
  static func missingJustifications(_ vector: Vector) -> [PrayerKind: Justification] {
    let zone = vector.location.timeZone
    let tolerance = vector.tolerance
    let low = vector.day.start(in: zone).addingTimeInterval(-lead)
    let high = vector.day.adding(days: 2).start(in: zone)
    let nextFirst = firstEvent(of: vector.day.adding(days: 1), vector)
    var result: [PrayerKind: Justification] = [:]
    var lastKept: Date?
    for kind in PrayerKind.allCases {
      guard let time = vector.expected[kind]?.date else {
        result[kind] = .doesNotOccur
        continue
      }
      let outside =
        time.timeIntervalSince(low) < tolerance || high.timeIntervalSince(time) <= tolerance
      let notAfter = lastKept.map { time.timeIntervalSince($0) <= tolerance } ?? false
      let afterNext = nextFirst.map { time.timeIntervalSince($0) > -tolerance } ?? false
      if outside {
        result[kind] = .outsideOwningSpan
      } else if notAfter {
        result[kind] = .notAfterPreviousKind
      } else if afterNext {
        result[kind] = .afterNextDaysFirstEvent
      }
      // The chain of kept kinds follows the exact rule, without the tolerance.
      if time >= low, time < high, lastKept.map({ time > $0 }) ?? true {
        lastKept = time
      }
    }
    return result
  }

  /// The earliest event the source keeps for `day`, calculated with SalahTimes directly and
  /// filtered as RFC 0002, section 4.3 describes; `nil` when the day can't be calculated.
  static func firstEvent(of day: CivilDay, _ vector: Vector) -> Date? {
    let zone = vector.location.timeZone
    guard day.adding(days: 1).start(in: zone) > day.start(in: zone),
      let gregorian = GregorianDay(year: day.year, month: day.month, day: day.day),
      let times = try? PrayerTimes(
        coordinates: Coordinates(
          latitude: vector.location.latitude, longitude: vector.location.longitude),
        day: gregorian, timeZone: zone, parameters: vector.parameters)
    else { return nil }
    let low = day.start(in: zone).addingTimeInterval(-lead)
    let high = day.adding(days: 2).start(in: zone)
    var kept: [Date] = []
    for kind in PrayerKind.allCases {
      guard let time = times[event(of: kind)].date, time >= low, time < high else { continue }
      if let last = kept.last, time <= last { continue }
      kept.append(time)
    }
    return kept.min()
  }

  static func event(of kind: PrayerKind) -> PrayerTimes.Event {
    switch kind {
    case .fajr: .fajr
    case .sunrise: .sunrise
    case .dhuhr: .dhuhr
    case .asr: .asr
    case .maghrib: .maghrib
    case .isha: .isha
    }
  }

  // MARK: Loading

  private static func load() -> Catalog {
    var catalog = Catalog()
    let presets: [String: [String: Any]]
    do {
      presets = try loadPresets(directory.appendingPathComponent("methods.json"))
    } catch {
      catalog.problems.append("methods.json: \(error)")
      presets = [:]
    }
    let folder = directory.appendingPathComponent("times")
    for name in fileNames {
      do {
        let data = try Data(contentsOf: folder.appendingPathComponent(name))
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any], root["schemaVersion"] as? Int == 1,
          root["kind"] as? String == "prayerTimes",
          let vectors = root["vectors"] as? [[String: Any]]
        else { throw LoadError("not a schemaVersion 1 prayerTimes file") }
        for raw in vectors {
          let id = raw["id"] as? String ?? "?"
          do {
            catalog.vectors.append(try vector(raw, file: name, id: id, presets: presets))
          } catch {
            catalog.problems.append("\(name) \(id): \(error)")
          }
        }
      } catch {
        catalog.problems.append("\(name): \(error)")
      }
    }
    return catalog
  }

  private static func vector(
    _ raw: [String: Any], file: String, id: String, presets: [String: [String: Any]]
  ) throws -> Vector {
    guard let input = raw["input"] as? [String: Any],
      let expectedObject = raw["expected"] as? [String: Any],
      let dateText = input["date"] as? String, let day = CivilDay(dateText),
      let zoneName = input["timeZone"] as? String, let zone = TimeZone(identifier: zoneName),
      let coordinates = input["coordinates"] as? [String: Any],
      let latitude = number(coordinates["latitude"]),
      let longitude = number(coordinates["longitude"]),
      let tolerance = number(raw["toleranceSeconds"])
    else { throw LoadError("malformed input") }
    var parameters = (input["parameters"] as? [String: Any]) ?? [:]
    if let method = input["method"] as? String {
      guard var preset = presets[method] else { throw LoadError("unknown method \(method)") }
      preset.merge(parameters) { _, override in override }
      parameters = preset
    }
    let decoded = try JSONDecoder().decode(
      CalculationParameters.self, from: JSONSerialization.data(withJSONObject: parameters))
    var expected: [PrayerKind: EventTime] = [:]
    for kind in PrayerKind.allCases {
      guard let value = expectedObject[kind.rawValue] else {
        throw LoadError("no expectation for \(kind)")
      }
      if let text = value as? String {
        guard let instant = InstantText.parse(text) else { throw LoadError("bad instant \(text)") }
        expected[kind] = .occurs(instant)
      } else if let object = value as? [String: Any],
        let reason = object["doesNotOccur"] as? String,
        let nonOccurrence = NonOccurrence(rawValue: reason)
      {
        expected[kind] = .doesNotOccur(nonOccurrence)
      } else {
        throw LoadError("bad expectation for \(kind)")
      }
    }
    return Vector(
      file: file, id: id, day: day,
      location: PrayerLocation(latitude: latitude, longitude: longitude, timeZone: zone),
      parameters: decoded, expected: expected, tolerance: tolerance)
  }

  /// The presets of `methods.json`, keyed by method name.
  private static func loadPresets(_ url: URL) throws -> [String: [String: Any]] {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let root = object as? [String: Any], let methods = root["methods"] as? [String: Any]
    else { throw LoadError("no methods") }
    var presets: [String: [String: Any]] = [:]
    for (key, value) in methods {
      guard let parameters = value as? [String: Any] else { continue }
      presets[key] = parameters
    }
    return presets
  }

  /// A JSON number. Linux's JSONSerialization gives `Int` for whole numbers, Darwin's gives
  /// `NSNumber`; both cast to one of these.
  private static func number(_ value: Any?) -> Double? {
    if let number = value as? Double { return number }
    if let number = value as? Int { return Double(number) }
    return nil
  }

  private struct LoadError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
  }
}
