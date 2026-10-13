import Foundation
import SalahCalculation
import Testing

@testable import SalahCore

/// Runs every vector in `Vectors/calculation` (RFC 0002, section 7).
///
/// The schema is SalahCore's (`Vectors/README.md`), with `input.settings`, a
/// `CalculationSettings` JSON value, in place of `input.source`. The schedule is
/// `PrayerSchedule(source: CalculationSource(settings), location:, iqama:)`, and the comparison
/// rules are those of SalahCore's `VectorTests`.
@Suite struct CalculationVectorTests {
  @Test(arguments: CalculationVector.all)
  func vector(_ vector: CalculationVector) throws {
    try vector.run()
  }

  @Test func everyFileLoads() {
    #expect(CalculationVector.loadErrors.isEmpty, "\(CalculationVector.loadErrors)")
    // A missing or renamed file must fail here.
    #expect(CalculationVector.all.count == 93)
    let ids = CalculationVector.all.map(\.id)
    #expect(Set(ids).count == ids.count, "vector ids must be unique")
    #expect(ids.allSatisfy { $0.hasPrefix("calculation.") })
  }
}

// MARK: - Loading

/// One calculation vector, with its input decoded by the library's own `Codable` types.
nonisolated struct CalculationVector: Sendable, CustomTestStringConvertible {
  struct Input: Decodable, Sendable {
    var location: PrayerLocation
    var settings: CalculationSettings
    var iqama: IqamaRules?
    var policy: StatePolicy?
    var query: VectorJSON
  }

  let file: String
  let id: String
  let input: Input?
  let inputError: String?
  let expected: VectorJSON

  var testDescription: String { id }

  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Vectors").appendingPathComponent("calculation")

  static let (all, loadErrors): ([CalculationVector], [String]) = {
    var vectors: [CalculationVector] = []
    var errors: [String] = []
    let names =
      (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
      .filter { $0.hasSuffix(".json") }.sorted() ?? []
    if names.isEmpty { errors.append("no vector files in calculation/") }
    for name in names {
      let path = "calculation/\(name)"
      do {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schemaVersion == 1 else {
          errors.append("\(path): unknown schemaVersion \(file.schemaVersion)")
          continue
        }
        vectors += file.vectors.map {
          CalculationVector(
            file: path, id: $0.id, input: $0.input, inputError: $0.inputError,
            expected: $0.expected)
        }
      } catch {
        errors.append("\(path): \(error)")
      }
    }
    return (vectors, errors)
  }()

  private struct File: Decodable {
    var schemaVersion: Int
    var vectors: [Raw]
  }

  /// A vector whose input may fail to decode; the failure is reported by its own test.
  private struct Raw: Decodable {
    var id: String
    var input: Input?
    var inputError: String?
    var expected: VectorJSON

    enum CodingKeys: String, CodingKey {
      case id, input, expected
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      expected = try container.decode(VectorJSON.self, forKey: .expected)
      do {
        input = try container.decode(Input.self, forKey: .input)
      } catch {
        input = nil
        inputError = "\(error)"
      }
    }
  }
}

// MARK: - Running

nonisolated extension CalculationVector {
  func run() throws {
    guard let input else {
      Issue.record("\(id): the input doesn't decode: \(inputError ?? "")")
      return
    }
    let schedule = PrayerSchedule(
      source: CalculationSource(input.settings), location: input.location, iqama: input.iqama)
    let policy = input.policy ?? StatePolicy()
    let query = input.query
    let context = "\(id) (\(file))"

    switch try query.required("type").requiredString() {
    case "day":
      try checkDay(schedule.day(try query.required("day").civilDay()), context)
    case "dayContaining":
      try checkDay(schedule.day(containing: try query.required("date").instant()), context)
    case "events":
      let result = schedule.events(
        from: try query.required("from").instant(),
        through: try query.required("through").instant())
      try checkEvents(result.events, expected.required("events"), "\(context): events")
      try checkCoverage(result.coverage, expected.required("coverage"), context)
    case "state":
      let state = schedule.state(
        at: try query.required("at").instant(), through: try query.required("through").instant(),
        policy: policy)
      try checkState(state, expected, schedule: schedule, context)
    case "refresh":
      try checkRefresh(schedule, query: query, policy: policy, context)
    case let other:
      Issue.record("\(context): unknown query type \(other)")
    }
  }

  func checkDay(_ availability: PrayerDayAvailability, _ context: String) throws {
    let expectedAvailability = try expected.required("availability").requiredString()
    switch availability {
    case .unavailable(let reason):
      #expect(expectedAvailability == "unavailable", "\(context): got unavailable(\(reason))")
      if let reasonJSON = expected["reason"] {
        #expect(reason.rawValue == reasonJSON.string, "\(context): reason \(reason)")
      }
    case .available(let day, let coverage):
      #expect(expectedAvailability == "available", "\(context): got available, \(coverage)")
      guard expectedAvailability == "available" else { return }
      #expect(day.timeZone.identifier == input?.location.timeZone.identifier)
      if let coverageJSON = expected["coverage"] {
        #expect(
          calculationDayCoverageJSON(coverage) == coverageJSON,
          "\(context): coverage \(calculationDayCoverageJSON(coverage)), expected \(coverageJSON)")
      }
      if let isFriday = expected["isFriday"] {
        #expect(day.isFriday == isFriday.bool, "\(context): isFriday")
      }
      if let events = expected["events"] {
        try checkEvents(day.events, events, "\(context): events")
      }
    }
  }

  func checkState(
    _ state: ScheduleState, _ expected: VectorJSON, schedule: PrayerSchedule, _ context: String
  ) throws {
    let availability = expected["availability"]?.string
    switch state {
    case .available(let prayerState, let coverage):
      if let availability {
        #expect(availability == "available", "\(context): got available")
      }
      try checkPrayerState(prayerState, expected, schedule: schedule, context)
      if let coverageJSON = expected["coverage"] {
        try checkCoverage(coverage, coverageJSON, context)
      }
    case .unavailable(let coverage, let changesAt):
      if let availability {
        #expect(availability == "unavailable", "\(context): got unavailable")
      }
      for field in ["previous", "latestPrayer", "next", "nextPrayer", "justStarted"] {
        if let value = expected[field] {
          #expect(value == .null, "\(context): got no \(field), expected \(value)")
        }
      }
      if let approaching = expected["isApproaching"] {
        #expect(approaching.bool == false, "\(context): isApproaching")
      }
      if let changes = expected["changesAt"] {
        try checkOptionalInstant(changesAt, changes, "\(context): changesAt")
      }
      if let coverageJSON = expected["coverage"] {
        try checkCoverage(coverage, coverageJSON, context)
      }
    }
    #expect(state.prayerState == nil || state.changesAt == state.prayerState?.changesAt)
  }

  func checkPrayerState(
    _ state: PrayerState, _ expected: VectorJSON, schedule: PrayerSchedule, _ context: String
  ) throws {
    let fields: [(String, PrayerEvent?)] = [
      ("previous", state.previous), ("latestPrayer", state.latestPrayer), ("next", state.next),
      ("nextPrayer", state.nextPrayer), ("justStarted", state.justStarted),
    ]
    for (name, event) in fields {
      guard let value = expected[name] else { continue }
      try checkOptionalEvent(event, value, "\(context): \(name)")
    }
    if let approaching = expected["isApproaching"] {
      #expect(state.isApproaching == approaching.bool, "\(context): isApproaching")
    }
    if let changes = expected["changesAt"] {
      try checkOptionalInstant(state.changesAt, changes, "\(context): changesAt")
    }
    for (key, value) in expected["statuses"]?.object ?? [:] {
      let parts = key.split(separator: "/")
      guard parts.count == 2, let day = CivilDay(String(parts[0])),
        let kind = PrayerKind(rawValue: String(parts[1])),
        let event = schedule.day(day).day?[kind]
      else {
        Issue.record("\(context): status key \(key) doesn't name a known event")
        continue
      }
      let status = calculationStatusText(state.status(of: event))
      #expect(status == value.string, "\(context): status of \(key) is \(status)")
    }
  }

  func checkRefresh(
    _ schedule: PrayerSchedule, query: VectorJSON, policy: StatePolicy, _ context: String
  ) throws {
    let from = try query.required("from").instant()
    let through = try query.required("through").instant()
    let strategy = try refreshStrategy(query["strategy"])
    let limit = query["limit"]?.number.map { Int($0) } ?? 96
    let plan: RefreshPlan
    do {
      plan = try schedule.refreshPlan(
        from: from, through: through, strategy: strategy, policy: policy, limit: limit)
    } catch {
      if let expectedError = expected["error"]?.string {
        #expect(calculationErrorText(error) == expectedError, "\(context): error \(error)")
      } else {
        Issue.record("\(context): unexpected error \(error)")
      }
      return
    }
    if let expectedError = expected["error"]?.string {
      Issue.record("\(context): expected error \(expectedError), got a plan")
      return
    }
    if let dates = expected["dates"]?.array {
      let expectedDates = try dates.map { try $0.instant() }
      #expect(
        plan.dates.map(vectorMilliseconds) == expectedDates.map(vectorMilliseconds),
        """
        \(context): dates
          got      \(plan.dates.map(InstantText.format))
          expected \(expectedDates.map(InstantText.format))
        """)
    }
    #expect(plan.dates == plan.entries.map(\.date))
    #expect(plan.entries.first?.date == plan.horizon.start)
    if let validUntil = expected["validUntil"] {
      try checkOptionalInstant(plan.validUntil, validUntil, "\(context): validUntil")
    }
    if let truncated = expected["isTruncated"] {
      #expect(plan.isTruncated == truncated.bool, "\(context): isTruncated")
    }
    for check in expected["entries"]?.array ?? [] {
      guard let index = check["index"]?.number.map({ Int($0) }),
        plan.entries.indices.contains(index)
      else {
        Issue.record("\(context): an entry check has a missing or out-of-range index")
        continue
      }
      let entry = plan.entries[index]
      if let date = check["date"] {
        try checkOptionalInstant(entry.date, date, "\(context): entry \(index) date")
      }
      try checkState(entry.state, check, schedule: schedule, "\(context): entry \(index)")
    }
  }

  // MARK: Comparisons

  func checkEvents(_ events: [PrayerEvent], _ expected: VectorJSON, _ context: String) throws {
    let references = expected.array ?? []
    #expect(
      events.count == references.count,
      "\(context): got \(events.map(\.id)), expected \(references.count) events")
    for (event, reference) in zip(events, references) {
      try checkEvent(event, reference, context)
    }
  }

  func checkOptionalEvent(_ event: PrayerEvent?, _ expected: VectorJSON, _ context: String) throws {
    switch (event, expected) {
    case (nil, .null): return
    case (nil, _): Issue.record("\(context): got null, expected \(expected)")
    case (let event?, .null): Issue.record("\(context): got \(event.id), expected null")
    case (let event?, _): try checkEvent(event, expected, context)
    }
  }

  func checkEvent(_ event: PrayerEvent, _ expected: VectorJSON, _ context: String) throws {
    #expect(
      event.scheduleDay == (try expected.required("day").civilDay()),
      "\(context): owning day of \(event.id)")
    #expect(
      event.kind.rawValue == (try expected.required("kind").requiredString()),
      "\(context): kind of \(event.id)")
    try checkOptionalInstant(event.time, try expected.required("time"), "\(context): time")
    try checkOptionalInstant(
      event.iqama, try expected.required("iqama"), "\(context): iqama of \(event.id)")
    #expect(
      event.observance.rawValue == (try expected.required("observance").requiredString()),
      "\(context): observance of \(event.id)")
  }

  func checkOptionalInstant(_ date: Date?, _ expected: VectorJSON, _ context: String) throws {
    switch (date, expected) {
    case (nil, .null): return
    case (let date?, .null):
      Issue.record("\(context): got \(InstantText.format(date)), expected null")
    case (nil, _): Issue.record("\(context): got null, expected \(expected)")
    case (let date?, _):
      let instant = try expected.instant()
      #expect(
        vectorMilliseconds(date) == vectorMilliseconds(instant),
        "\(context): got \(InstantText.format(date)), expected \(InstantText.format(instant))")
    }
  }

  func checkCoverage(_ coverage: ScheduleCoverage, _ expected: VectorJSON, _ context: String)
    throws
  {
    if let requested = expected["requested"]?.array {
      #expect(requested.count == 2, "\(context): requested needs two instants")
      if requested.count == 2 {
        try checkOptionalInstant(
          coverage.requested.start, requested[0], "\(context): requested start")
        try checkOptionalInstant(coverage.requested.end, requested[1], "\(context): requested end")
      }
    }
    if let known = expected["known"]?.array {
      let expectedKnown = try known.map { pair in
        try (pair.array ?? []).map { vectorMilliseconds(try $0.instant()) }
      }
      let actualKnown = coverage.knownIntervals.map {
        [vectorMilliseconds($0.start), vectorMilliseconds($0.end)]
      }
      #expect(
        actualKnown == expectedKnown,
        "\(context): known intervals \(coverage.knownIntervals.map(vectorIntervalText))")
    }
    if let gaps = expected["gaps"]?.array {
      let expectedGaps = try gaps.map { gap in
        VectorGap(
          start: vectorMilliseconds(try gap.required("start").instant()),
          end: vectorMilliseconds(try gap.required("end").instant()),
          day: try gap.required("day").civilDay(),
          kinds: Set(try (gap.required("kinds").array ?? []).map { try $0.requiredString() }),
          reason: try gap.required("reason").requiredString())
      }
      let actualGaps = coverage.gaps.map {
        VectorGap(
          start: vectorMilliseconds($0.interval.start), end: vectorMilliseconds($0.interval.end),
          day: $0.day, kinds: Set($0.kinds.map(\.rawValue)), reason: $0.reason.rawValue)
      }
      #expect(
        actualGaps == expectedGaps,
        """
        \(context): gaps
          got      \(actualGaps)
          expected \(expectedGaps)
        """)
    }
    #expect(coverage.isComplete == coverage.gaps.isEmpty)
  }

  func refreshStrategy(_ json: VectorJSON?) throws -> RefreshStrategy {
    guard let json, json != .null, json.string != "stateChanges" else { return .stateChanges }
    let steps = try json.required("steps")
    return .steps(
      fine: .seconds(try steps.required("fine").requiredNumber()),
      coarse: .seconds(try steps.required("coarse").requiredNumber()),
      window: .seconds(try steps.required("window").requiredNumber()))
  }
}

/// An instant as whole milliseconds since 1970, the vectors' precision.
nonisolated func vectorMilliseconds(_ date: Date) -> Int64 {
  Int64((date.timeIntervalSince1970 * 1000).rounded())
}

nonisolated func vectorIntervalText(_ interval: DateInterval) -> String {
  "[\(InstantText.format(interval.start)), \(InstantText.format(interval.end))]"
}

nonisolated struct VectorGap: Equatable, CustomStringConvertible {
  var start: Int64
  var end: Int64
  var day: CivilDay
  var kinds: Set<String>
  var reason: String

  var description: String {
    let start = InstantText.format(Date(timeIntervalSince1970: Double(self.start) / 1000))
    let end = InstantText.format(Date(timeIntervalSince1970: Double(self.end) / 1000))
    return "[\(start), \(end)) \(day) \(kinds.sorted()) \(reason)"
  }
}

nonisolated func calculationDayCoverageJSON(_ coverage: DayCoverage) -> VectorJSON {
  switch coverage {
  case .complete: return .string("complete")
  case .partial(let missing):
    return .object([
      "partial": .object(
        missing.reduce(into: [:]) { $0[$1.key.rawValue] = .string($1.value.rawValue) })
    ])
  }
}

nonisolated func calculationStatusText(_ status: PrayerEventStatus) -> String {
  switch status {
  case .passed: "passed"
  case .justStarted: "justStarted"
  case .next(approaching: false): "next"
  case .next(approaching: true): "nextApproaching"
  case .upcoming: "upcoming"
  }
}

nonisolated func calculationErrorText(_ error: RefreshPlanError) -> String {
  switch error {
  case .nonPositiveHorizon: "nonPositiveHorizon"
  case .limitTooSmall: "limitTooSmall"
  case .invalidStrategy: "invalidStrategy"
  }
}

// MARK: - A small JSON value

/// Any JSON value, for the parts of a vector that aren't library types.
nonisolated enum VectorJSON: Decodable, Equatable, Sendable, CustomStringConvertible {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([VectorJSON])
  case object([String: VectorJSON])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([VectorJSON].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: VectorJSON].self) {
      self = .object(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else {
      self = .number(try container.decode(Double.self))
    }
  }

  subscript(key: String) -> VectorJSON? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  var string: String? { if case .string(let value) = self { value } else { nil } }
  var number: Double? { if case .number(let value) = self { value } else { nil } }
  var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
  var array: [VectorJSON]? { if case .array(let value) = self { value } else { nil } }
  var object: [String: VectorJSON]? { if case .object(let value) = self { value } else { nil } }

  var description: String {
    switch self {
    case .null: "null"
    case .bool(let value): "\(value)"
    case .number(let value): "\(value)"
    case .string(let value): "\"\(value)\""
    case .array(let value): "[\(value.map(\.description).joined(separator: ", "))]"
    case .object(let value):
      "{\(value.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", "))}"
    }
  }

  func required(_ key: String) throws -> VectorJSON {
    guard let value = self[key] else { throw VectorFormatError.missing(key, in: self) }
    return value
  }

  func requiredString() throws -> String {
    guard let value = string else { throw VectorFormatError.type("string", self) }
    return value
  }

  func requiredNumber() throws -> Double {
    guard let value = number else { throw VectorFormatError.type("number", self) }
    return value
  }

  func instant() throws -> Date {
    guard let text = string, let date = InstantText.parse(text) else {
      throw VectorFormatError.type("instant", self)
    }
    return date
  }

  func civilDay() throws -> CivilDay {
    guard let text = string, let day = CivilDay(text) else {
      throw VectorFormatError.type("day", self)
    }
    return day
  }
}

nonisolated enum VectorFormatError: Error, CustomStringConvertible {
  case missing(String, in: VectorJSON)
  case type(String, VectorJSON)

  var description: String {
    switch self {
    case .missing(let key, let json): "missing key \(key) in \(json)"
    case .type(let type, let value): "expected \(type), found \(value)"
    }
  }
}
