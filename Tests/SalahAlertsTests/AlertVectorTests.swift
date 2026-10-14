import Foundation
import SalahAlerts
import SalahCalculation
import SalahCore
import Testing

/// Runs every vector in `Vectors/alerts` through the public planner.
///
/// `Vectors/README.md` ("Alert vectors") documents the schema; this file is its Swift reading.
@Suite struct AlertVectorTests {
  nonisolated static let loaded = VectorFiles.load("alerts")

  @Test(arguments: loaded.vectors.map(AlertVector.init))
  func vector(_ vector: AlertVector) throws {
    try vector.run()
  }

  @Test func everyFileLoads() {
    #expect(Self.loaded.errors.isEmpty, "\(Self.loaded.errors)")
    // 69 planning vectors in five files, including handled occurrences after a rollback.
    #expect(Self.loaded.vectors.count == 69)
    let ids = Self.loaded.vectors.map(\.id)
    #expect(Set(ids).count == ids.count, "vector ids must be unique")
    #expect(ids.allSatisfy { $0.hasPrefix("alerts.") })
  }
}

nonisolated struct AlertVector: Sendable, CustomTestStringConvertible {
  let vector: VectorFiles.Vector

  init(_ vector: VectorFiles.Vector) {
    self.vector = vector
  }

  var testDescription: String { vector.id }

  /// The settings table of the README: a day's own table, else the top level; Jumu'ah's own
  /// settings, else Dhuhr's.
  struct SettingsTable: Decodable, Sendable {
    var kinds: [PrayerKind: AlertSettings]?
    var jumuah: AlertSettings?
    var days: [String: SettingsTable]?

    func settings(for subject: AlertSubject) -> AlertSettings? {
      let level = days?[subject.scheduleDay.description] ?? self
      if subject.observance == .jumuah, let jumuah = level.jumuah { return jumuah }
      return level.kinds?[subject.prayer]
    }
  }

  func run() throws {
    let input = vector.input
    let expected = vector.expected
    let context = "\(vector.id) (\(vector.file))"
    let location = try input.required("location").decode(PrayerLocation.self)
    let source: any PrayerSource
    if let calculation = input["calculation"] {
      source = CalculationSource(try calculation.decode(CalculationSettings.self))
    } else {
      source = try input.required("source").decode(TimetableSource.self)
    }
    let schedule = PrayerSchedule(source: source, location: location)
    let table = try input.required("alertSettings").decode(SettingsTable.self)
    let namespace = try input.required("namespace").requiredString()
    let maximum = Duration.seconds(input["maximumReminderOffset"]?.number ?? 7_200)
    let query = try input.required("query")

    let alertSchedule: AlertSchedule
    do {
      alertSchedule = try AlertPlanner().schedule(
        schedule, namespace: namespace, from: try query.required("from").instant(),
        to: try query.required("to").instant(), maximumReminderOffset: maximum,
        settings: table.settings(for:))
    } catch {
      guard let expectedError = expected["error"] else {
        Issue.record("\(context): unexpected error \(error)")
        return
      }
      #expect(errorJSON(error) == expectedError, "\(context): error \(error)")
      return
    }
    if let expectedError = expected["error"] {
      Issue.record("\(context): expected error \(expectedError), got a schedule")
      return
    }
    #expect(alertSchedule.namespace == namespace, "\(context): namespace")
    try checkInvariants(alertSchedule, context)

    switch try query.required("type").requiredString() {
    case "schedule":
      try checkInterval(
        alertSchedule.requestedRange, try expected.required("requested"), "\(context): requested")
      try checkAlerts(alertSchedule.alerts, try expected.required("alerts"), "\(context): alerts")
      try checkGaps(alertSchedule.gaps, try expected.required("gaps"), context)
    case "plan":
      var budget = AlertBudget()
      if let json = query["budget"] {
        if let value = json["maxPending"]?.number { budget.maxPending = Int(value) }
        if let value = json["nearTermWindow"]?.number { budget.nearTermWindow = .seconds(value) }
        if let value = json["horizon"]?.number { budget.horizon = .seconds(value) }
      }
      let now = try query.required("now").instant()
      let handled = try handledOccurrences(query, namespace: namespace)
      let plan = AlertPlanner().notificationPlan(
        alertSchedule, from: now, budget: budget, excluding: handled)
      try checkPlan(plan, schedule: alertSchedule, now: now, handled: handled, context)
    case let other:
      Issue.record("\(context): unknown query type \(other)")
    }
  }

  func checkPlan(
    _ plan: NotificationPlan, schedule: AlertSchedule, now: Date,
    handled: [AlertOccurrenceID: Date], _ context: String
  ) throws {
    let expected = vector.expected
    #expect(plan.namespace == schedule.namespace, "\(context): plan namespace")
    try checkInterval(
      plan.effectiveRange, try expected.required("effectiveRange"),
      "\(context): effectiveRange")
    try checkAlerts(plan.alerts, try expected.required("alerts"), "\(context): plan alerts")
    // Omitted: eligible alerts in the effective range the budget didn't select.
    let selected = Set(plan.alerts.map(\.occurrenceID))
    let omitted = schedule.alerts.filter {
      plan.effectiveRange.start <= $0.fireDate && $0.fireDate < plan.effectiveRange.end
        && !selected.contains($0.occurrenceID)
        && !(handled[$0.occurrenceID].map { now < $0 } ?? false)
    }
    let expectedOmitted = try expected.required("omitted").requiredArray()
    #expect(
      omitted.count == expectedOmitted.count,
      "\(context): omitted \(omitted.map(reference)), expected \(expectedOmitted.count)")
    for (alert, reference) in zip(omitted, expectedOmitted) {
      #expect(
        self.reference(alert) == (try reference.required("id").requiredString()),
        "\(context): omitted \(self.reference(alert))")
      try checkInstant(
        alert.fireDate, try reference.required("fireDate"), "\(context): omitted fire date")
    }
    try checkInstant(
      plan.coveredUntil, try expected.required("coveredUntil"), "\(context): coveredUntil")
    let expectedCoverage = try expected.required("coverageByKind").object ?? [:]
    #expect(
      Set(plan.coverageByKind.keys.map(\.rawValue)) == Set(expectedCoverage.keys),
      "\(context): coverageByKind kinds \(plan.coverageByKind.keys.map(\.rawValue).sorted())")
    for (kind, date) in plan.coverageByKind {
      guard let value = expectedCoverage[kind.rawValue] else { continue }
      try checkInstant(date, value, "\(context): coverageByKind[\(kind)]")
    }
  }

  // MARK: Invariants every schedule keeps, whatever the vector checks

  func handledOccurrences(_ query: JSON, namespace: String) throws -> [AlertOccurrenceID: Date] {
    var result: [AlertOccurrenceID: Date] = [:]
    for record in try query["handled"]?.requiredArray() ?? [] {
      let owner = try record["namespace"]?.requiredString() ?? namespace
      let reference = try record.required("id").requiredString()
      let identity = try #require(
        NotificationIdentity(requestIdentifier: "\(owner)/\(reference)", prefix: ""))
      let occurrence = AlertOccurrenceID(
        notification: identity, fireDate: try record.required("fireDate").instant())
      #expect(result[occurrence] == nil, "handled occurrences are unique")
      result[occurrence] = try record.required("handledAt").instant()
    }
    return result
  }

  func checkInvariants(_ schedule: AlertSchedule, _ context: String) throws {
    let range = schedule.requestedRange
    for alert in schedule.alerts {
      #expect(
        range.start <= alert.fireDate && alert.fireDate < range.end,
        "\(context): \(reference(alert)) is outside the requested range")
      #expect(alert.id.namespace == schedule.namespace)
      #expect(alert.id.scheduleDay == alert.event.scheduleDay)
      #expect(alert.id.prayer == alert.event.kind)
      #expect(
        alert.occurrenceID == AlertOccurrenceID(notification: alert.id, fireDate: alert.fireDate))
    }
    let ordered = zip(schedule.alerts, schedule.alerts.dropFirst()).allSatisfy {
      ($0.fireDate, $0.id) < ($1.fireDate, $1.id)
    }
    #expect(ordered, "\(context): alerts are in fire-date, then identity order")
  }

  // MARK: Comparisons

  func reference(_ alert: PlannedAlert) -> String {
    "\(alert.id.scheduleDay)/\(alert.id.prayer.rawValue)/\(alert.kind.rawValue)"
  }

  func checkAlerts(_ alerts: [PlannedAlert], _ expected: JSON, _ context: String) throws {
    let references = try expected.requiredArray()
    #expect(
      alerts.count == references.count,
      "\(context): got \(alerts.map(reference)), expected \(references.count) alerts")
    for (alert, ref) in zip(alerts, references) {
      let id = try ref.required("id").requiredString()
      #expect(reference(alert) == id, "\(context): got \(reference(alert)), expected \(id)")
      try checkInstant(alert.fireDate, try ref.required("fireDate"), "\(context): \(id) fireDate")
      try checkInstant(alert.event.time, try ref.required("event"), "\(context): \(id) event")
      #expect(
        alert.event.observance.rawValue == (try ref.required("observance").requiredString()),
        "\(context): \(id) observance")
      #expect(
        soundJSON(alert.sound) == (try ref.required("sound")), "\(context): \(id) sound")
    }
  }

  func checkGaps(_ gaps: [AlertGap], _ expected: JSON, _ context: String) throws {
    let references = try expected.requiredArray()
    #expect(
      gaps.count == references.count,
      "\(context): got \(gaps.count) gaps, expected \(references.count): \(gaps)")
    for (gap, ref) in zip(gaps, references) {
      try checkInstant(gap.interval.start, try ref.required("start"), "\(context): gap start")
      try checkInstant(gap.interval.end, try ref.required("end"), "\(context): gap end")
      #expect(
        gap.kind.rawValue == (try ref.required("kind").requiredString()), "\(context): gap kind")
      #expect(gap.day == (try ref.required("day").civilDay()), "\(context): gap day")
      let prayers = Set(try ref.required("prayers").requiredArray().map { try $0.requiredString() })
      #expect(Set(gap.prayers.map(\.rawValue)) == prayers, "\(context): gap prayers")
      #expect(
        gap.reason.rawValue == (try ref.required("reason").requiredString()),
        "\(context): gap reason")
    }
  }

  func checkInterval(_ interval: DateInterval, _ expected: JSON, _ context: String) throws {
    let bounds = try expected.requiredArray()
    guard bounds.count == 2 else {
      Issue.record("\(context): expected [start, end]")
      return
    }
    try checkInstant(interval.start, bounds[0], "\(context) start")
    try checkInstant(interval.end, bounds[1], "\(context) end")
  }

  func checkInstant(_ date: Date, _ expected: JSON, _ context: String) throws {
    let value = try expected.instant()
    #expect(
      Instant.milliseconds(date) == Instant.milliseconds(value),
      "\(context): got \(Instant.text(date)), expected \(Instant.text(value))")
  }

  func soundJSON(_ sound: AlertSound) -> JSON {
    switch sound {
    case .none: .string("none")
    case .system: .string("system")
    case .named(let name): .object(["named": .string(name)])
    }
  }

  func errorJSON(_ error: any Error) -> JSON {
    guard let error = error as? AlertPlanningError else { return .string("\(error)") }
    switch error {
    case .invalidNamespace(let namespace):
      return .object(["invalidNamespace": .string(namespace)])
    case .invalidMaximumReminderOffset(let offset):
      return .object(["invalidMaximumReminderOffset": .number(seconds(offset))])
    case .reminderOffsetOutOfRange(let subject, let kind, let offset):
      return .object([
        "reminderOffsetOutOfRange": .object([
          "day": .string(subject.scheduleDay.description),
          "prayer": .string(subject.prayer.rawValue),
          "observance": .string(subject.observance.rawValue),
          "kind": .string(kind.rawValue),
          "offset": .number(seconds(offset)),
        ])
      ])
    }
  }

  func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }
}
