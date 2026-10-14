#if canImport(UserNotifications) && !os(tvOS)
  import Foundation
  import SalahAlerts
  import SalahCore
  import Testing
  import UserNotifications

  /// Runs every vector in `Vectors/reconciliation` through `NotificationScheduler` against the
  /// modelled center of `Vectors/README.md` ("Reconciliation vectors").
  @Suite struct ReconciliationVectorTests {
    nonisolated static let loaded = VectorFiles.load("reconciliation")

    @Test(arguments: loaded.vectors.map(ReconciliationVector.init))
    func vector(_ vector: ReconciliationVector) async throws {
      try await vector.run()
    }

    @Test func everyFileLoads() {
      #expect(Self.loaded.errors.isEmpty, "\(Self.loaded.errors)")
      // 60 scheduler vectors in nine files.
      #expect(Self.loaded.vectors.count == 60)
      let ids = Self.loaded.vectors.map(\.id)
      #expect(Set(ids).count == ids.count, "vector ids must be unique")
      #expect(ids.allSatisfy { $0.hasPrefix("reconciliation.") })
    }
  }

  nonisolated struct ReconciliationVector: Sendable, CustomTestStringConvertible {
    let vector: VectorFiles.Vector

    init(_ vector: VectorFiles.Vector) {
      self.vector = vector
    }

    var testDescription: String { vector.id }

    func run() async throws {
      let input = vector.input
      let expected = vector.expected
      let context = "\(vector.id) (\(vector.file))"
      let steps = try input.required("steps").requiredArray()
      guard let first = steps.first else {
        Issue.record("\(context): no steps")
        return
      }
      let clock = TestClock(try first.required("now").instant())
      let center = try makeCenter(input["center"] ?? .object([:]), clock: clock)
      let config = try input.required("scheduler")
      let prefix = try config.required("identifierPrefix").requiredString()
      let namespace = try config.required("namespace").requiredString()
      let retention = config["deliveredRetention"]?.number.map { Duration.seconds($0) }
      let scheduler = NotificationScheduler(
        identifierPrefix: prefix, namespace: namespace,
        threadIdentifier: config["threadIdentifier"]?.string, center: center,
        deliveredRetention: retention, now: { clock.now })

      var reports: [JSON] = []
      var index = 0
      while index < steps.count {
        var group = [steps[index]]
        while index + group.count < steps.count,
          steps[index + group.count]["duringPrevious"]?.bool == true
        {
          group.append(steps[index + group.count])
        }
        let step = group[0]
        clock.set(try step.required("now").instant())
        let readBackAt = try step["readBackAt"].map { try $0.instant() }
        if group.count == 1 {
          center.beginStep(readBackAt: readBackAt)
          reports.append(try await runStep(step, scheduler: scheduler))
        } else {
          reports += try await runOverlapping(
            group, scheduler: scheduler, center: center, readBackAt: readBackAt, context)
        }
        index += group.count
      }

      let expectedReports = try expected.required("reports").requiredArray()
      #expect(reports.count == expectedReports.count, "\(context): one report per step")
      for (offset, (report, wanted)) in zip(reports, expectedReports).enumerated() {
        try compare(report, wanted, "\(context): report \(offset)")
      }
      try compare(.array(center.calls), try expected.required("calls"), "\(context): calls")
      try comparePending(center.pending, try expected.required("pending"), context)
      let delivered = center.delivered.map {
        JSON.object(["id": .string($0.identifier), "date": .string(Instant.text($0.date))])
      }
      try compare(.array(delivered), try expected.required("delivered"), "\(context): delivered")
    }

    // MARK: Steps

    func runStep(_ step: JSON, scheduler: NotificationScheduler) async throws -> JSON {
      let wording = step["wording"]?.string ?? "v1"
      let content = Self.content(wording: wording)
      do {
        if let plan = step["apply"] {
          let report = try await scheduler.apply(
            try makePlan(plan, now: try step.required("now").instant()), content: content)
          return Self.json(report)
        }
        let alerts = try step.required("deliver").requiredArray().map {
          try makeAlert($0, namespace: scheduler.namespace)
        }
        return Self.json(try await scheduler.deliver(alerts, content: content))
      } catch let error as NotificationSchedulerError {
        switch error {
        case .namespaceMismatch: return .object(["error": "namespaceMismatch"])
        case .duplicateIdentity: return .object(["error": "duplicateIdentity"])
        }
      }
    }

    /// The first step's batch is held in its `suspendAtCall`-th call while the later steps are
    /// submitted, then released.
    func runOverlapping(
      _ group: [JSON], scheduler: NotificationScheduler, center: ModelCenter, readBackAt: Date?,
      _ context: String
    ) async throws -> [JSON] {
      guard let suspendAt = group[0]["suspendAtCall"]?.number.map({ Int($0) }) else {
        Issue.record("\(context): an overlapping group needs suspendAtCall")
        return []
      }
      guard readBackAt == nil, group.allSatisfy({ $0["readBackAt"] == nil }) else {
        Issue.record("\(context): an overlapping group never sets readBackAt")
        return []
      }
      center.beginStep(readBackAt: readBackAt, suspendAtCall: suspendAt)
      let submitted = await scheduler.submittedApplies
      let first = Task { try await runStep(group[0], scheduler: scheduler) }
      try await waitUntil(context) { center.isSuspended }
      var later: [Task<JSON, any Error>] = []
      var accepted = submitted + 1
      for step in group.dropFirst() {
        let finished = Flag()
        later.append(
          Task {
            defer { finished.set() }
            return try await runStep(step, scheduler: scheduler)
          })
        // Submitted in order: each apply registers before the next one starts. One that
        // validation rejects never registers; it finishes at once instead.
        let next = accepted + 1
        try await waitUntil(context) {
          await scheduler.submittedApplies == next || finished.value
        }
        if await scheduler.submittedApplies == accepted + 1 { accepted += 1 }
      }
      center.release()
      var reports = [try await first.value]
      for task in later { reports.append(try await task.value) }
      return reports
    }

    /// A flag one task sets and another reads.
    final class Flag: @unchecked Sendable {
      // @unchecked: `isSet` is only read and written while holding `lock`.
      private let lock = NSLock()
      private var isSet = false
      var value: Bool { lock.withLock { isSet } }
      func set() { lock.withLock { isSet = true } }
    }

    func waitUntil(_ context: String, _ condition: @Sendable () async -> Bool) async throws {
      for _ in 0..<2_000 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
      }
      Issue.record("\(context): timed out waiting for the overlapping applies")
    }

    // MARK: Building inputs

    func makeCenter(_ json: JSON, clock: TestClock) throws -> ModelCenter {
      let status: UNAuthorizationStatus =
        switch json["authorization"]?.string ?? "authorized" {
        case "authorized": .authorized
        case "provisional": .provisional
        case "denied": .denied
        case "notDetermined": .notDetermined
        #if os(iOS)
          case "ephemeral": .ephemeral
        #endif
        default: throw VectorError.type("authorization", json["authorization"] ?? .null)
        }
      let pending = try (json["pending"]?.array ?? []).map { request in
        ModelCenter.request(
          try request.required("id").requiredString(),
          fireDate: try request.required("fireDate").instant(),
          title: try request.required("title").requiredString(),
          body: try request.required("body").requiredString(),
          thread: request["thread"]?.string ?? "")
      }
      let delivered = try (json["delivered"]?.array ?? []).map { record in
        DeliveredNotificationRecord(
          identifier: try record.required("id").requiredString(),
          date: try record.required("date").instant())
      }
      let center = ModelCenter(
        clock: clock, authorization: status, pending: pending, delivered: delivered)
      func strings(_ key: String) throws -> Set<String> {
        Set(try (json[key]?.array ?? []).map { try $0.requiredString() })
      }
      center.configure(
        failAdds: try strings("failAdds"), ignoreAdds: try strings("ignoreAdds"),
        dropAdds: try strings("dropAdds"),
        failReads: Set((json["failReads"]?.array ?? []).compactMap { $0.number.map { Int($0) } }))
      return center
    }

    func makePlan(_ json: JSON, now: Date) throws -> NotificationPlan {
      let namespace = try json.required("namespace").requiredString()
      let coveredUntil = try json.required("coveredUntil").instant()
      let alerts = try json.required("alerts").requiredArray().map {
        try makeAlert($0, namespace: namespace)
      }
      return NotificationPlan(
        namespace: namespace,
        effectiveRange: DateInterval(start: now, end: max(now, coveredUntil)), alerts: alerts,
        coveredUntil: coveredUntil, coverageByKind: [:])
    }

    func makeAlert(_ json: JSON, namespace: String) throws -> PlannedAlert {
      let parts = try json.required("id").requiredString().split(separator: "/").map(String.init)
      guard parts.count == 3, let day = CivilDay(parts[0]),
        let prayer = PrayerKind(rawValue: parts[1]),
        let kind = AlertKind(rawValue: parts[2])
      else { throw VectorError.type("alert id", json) }
      let fireDate = try json.required("fireDate").instant()
      let identity = NotificationIdentity(
        namespace: json["namespace"]?.string ?? namespace, scheduleDay: day, prayer: prayer,
        kind: kind)
      return PlannedAlert(
        id: identity, event: PrayerEvent(scheduleDay: day, kind: prayer, time: fireDate),
        fireDate: fireDate, sound: .system)
    }

    /// The README's content: the prayer as the title, "<wording> <kind>" as the body.
    static func content(wording: String) -> @Sendable (PlannedAlert) -> UNMutableNotificationContent
    {
      { alert in
        let content = UNMutableNotificationContent()
        content.title = alert.id.prayer.rawValue
        content.body = "\(wording) \(alert.kind.rawValue)"
        return content
      }
    }

    // MARK: Reports as JSON

    static func occurrence(_ id: AlertOccurrenceID) -> JSON {
      .object([
        "id": .string(
          "\(id.notification.scheduleDay)/\(id.notification.prayer.rawValue)/\(id.notification.kind.rawValue)"
        ),
        "fireDate": .string(Instant.text(id.fireDate)),
      ])
    }

    static func failures(_ failures: [NotificationIdentity: NotificationApplyFailure]) -> JSON {
      var object: [String: JSON] = [:]
      for (identity, failure) in failures {
        let key = "\(identity.scheduleDay)/\(identity.prayer.rawValue)/\(identity.kind.rawValue)"
        object[key] =
          switch failure {
          case .notAuthorized: "notAuthorized"
          case .addFailed: "addFailed"
          case .unconfirmed: "unconfirmed"
          }
      }
      return .object(object)
    }

    static func json(_ report: NotificationApplyReport) -> JSON {
      .object([
        "superseded": .bool(report.superseded),
        "verifiedAt": .string(Instant.text(report.verifiedAt)),
        "confirmed": .array(report.confirmed.map(occurrence)),
        "failures": failures(report.failures),
        "confirmedCoveredUntil": report.confirmedCoveredUntil.map { .string(Instant.text($0)) }
          ?? .null,
      ])
    }

    static func json(_ report: NotificationDeliveryReport) -> JSON {
      .object([
        "posted": .array(report.posted.map(occurrence)),
        "skipped": .array(report.skipped.map(occurrence)),
        "failures": failures(report.failures),
      ])
    }

    // MARK: Comparison

    /// Compares two JSON values, instants as instants (strings that parse as instants).
    func compare(_ got: JSON, _ wanted: JSON, _ context: String) throws {
      #expect(Self.same(got, wanted), "\(context):\n  got      \(got)\n  expected \(wanted)")
    }

    static func same(_ got: JSON, _ wanted: JSON) -> Bool {
      switch (got, wanted) {
      case (.string(let a), .string(let b)):
        if a == b { return true }
        guard let x = Instant.parse(a), let y = Instant.parse(b) else { return false }
        return Instant.milliseconds(x) == Instant.milliseconds(y)
      case (.array(let a), .array(let b)):
        return a.count == b.count && zip(a, b).allSatisfy(same)
      case (.object(let a), .object(let b)):
        return Set(a.keys) == Set(b.keys)
          && a.allSatisfy { key, value in
            b[key].map { same(value, $0) } ?? false
          }
      default:
        return got == wanted
      }
    }

    func comparePending(
      _ pending: [String: UNNotificationRequest], _ wanted: JSON, _ context: String
    ) throws {
      let got = pending.keys.sorted().compactMap { pending[$0] }.map { request in
        JSON.object([
          "id": .string(request.identifier),
          "fireDate": ModelCenter.fireDate(of: request).map { .string(Instant.text($0)) } ?? .null,
          "title": .string(request.content.title), "body": .string(request.content.body),
          "thread": .string(request.content.threadIdentifier),
        ])
      }
      try compare(.array(got), wanted, "\(context): pending")
    }
  }
#endif
