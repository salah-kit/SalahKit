#if canImport(UserNotifications) && !os(tvOS)
  import Foundation
  import SalahCore
  // UNNotificationRequest and UNNotificationContent aren't marked Sendable, but they are
  // immutable once created: a request copies the content it's given, and the scheduler never
  // mutates a content after building its request. Passing them between the scheduler's actor and
  // the center can't race, so the import doesn't ask for Sendable conformances.
  @preconcurrency import UserNotifications

  /// What ``NotificationScheduler`` reads from a delivered notification: its identifier and
  /// when it was delivered.
  nonisolated public struct DeliveredNotificationRecord: Hashable, Sendable {
    /// The request's identifier.
    public var identifier: String
    /// When the notification was delivered.
    public var date: Date

    /// Creates a record.
    public init(identifier: String, date: Date) {
      self.identifier = identifier
      self.date = date
    }
  }

  /// The part of `UNUserNotificationCenter` that ``NotificationScheduler`` uses.
  ///
  /// `UNUserNotificationCenter` conforms. Tests conform a fake to inject failed adds, stale
  /// read-backs and denied authorization. Nothing here requests authorization: that stays with
  /// the app.
  nonisolated public protocol AlertNotificationCenter: AnyObject, Sendable {
    /// The app's notification authorization.
    func authorizationStatus() async -> UNAuthorizationStatus
    /// The pending requests. `UNUserNotificationCenter` never throws; a fake can.
    func pendingNotificationRequests() async throws -> [UNNotificationRequest]
    /// Adds a request, replacing a pending one with the same identifier.
    func add(_ request: UNNotificationRequest) async throws
    /// Removes pending requests.
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    /// The delivered notifications' identifiers and dates.
    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord]
    /// Removes delivered notifications.
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
  }

  extension UNUserNotificationCenter: AlertNotificationCenter {
    /// The authorization status from the center's notification settings.
    public func authorizationStatus() async -> UNAuthorizationStatus {
      await notificationSettings().authorizationStatus
    }

    /// The delivered notifications' identifiers and dates.
    public func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
      await deliveredNotifications().map {
        DeliveredNotificationRecord(identifier: $0.request.identifier, date: $0.date)
      }
    }
  }

  /// Why one alert of a plan isn't confirmed.
  nonisolated public enum NotificationApplyFailure: Hashable, Sendable {
    /// Authorization doesn't allow alerts, so nothing was added.
    case notAuthorized
    /// The center rejected the request, with the error's description.
    case addFailed(String)
    /// The read-back found no matching request: it is missing, an older request with the same
    /// identifier is still there, or the read-back failed.
    case unconfirmed
  }

  /// What a ``NotificationScheduler/apply(_:content:)`` call confirmed.
  ///
  /// It never claims more than the read-back showed. Neither field proves that a notification
  /// was presented or heard.
  nonisolated public struct NotificationApplyReport: Hashable, Sendable {
    /// When the scheduler read the pending requests back, or stopped.
    public var verifiedAt: Date
    /// The plan's alerts after ``verifiedAt`` whose matching requests the read-back found, in
    /// plan order.
    public var confirmed: [AlertOccurrenceID]
    /// Why other alerts aren't confirmed.
    public var failures: [NotificationIdentity: NotificationApplyFailure]
    /// Whether a later plan replaced this one before its batch finished; then nothing is
    /// confirmed.
    public var superseded: Bool
    /// Every alert of the plan from ``verifiedAt`` until this instant has a matching pending
    /// request; `nil` when the read-back couldn't establish it.
    ///
    /// Recomputed from the read-back: a denied authorization, a failed add, an old or missing
    /// request shortens it, and it never exceeds the plan's ``NotificationPlan/coveredUntil``.
    public var confirmedCoveredUntil: Date?

    /// Creates a report.
    public init(
      verifiedAt: Date, confirmed: [AlertOccurrenceID],
      failures: [NotificationIdentity: NotificationApplyFailure], superseded: Bool,
      confirmedCoveredUntil: Date?
    ) {
      self.verifiedAt = verifiedAt
      self.confirmed = confirmed
      self.failures = failures
      self.superseded = superseded
      self.confirmedCoveredUntil = confirmedCoveredUntil
    }
  }

  /// What a ``NotificationScheduler/deliver(_:content:)`` call did with each alert.
  nonisolated public struct NotificationDeliveryReport: Hashable, Sendable {
    /// Alerts posted at once, by fire date and identity.
    public var posted: [AlertOccurrenceID]
    /// Alerts left alone because a pending request will deliver them, or this occurrence was
    /// already delivered.
    public var skipped: [AlertOccurrenceID]
    /// Alerts that couldn't be posted.
    public var failures: [NotificationIdentity: NotificationApplyFailure]

    /// Creates a report.
    public init(
      posted: [AlertOccurrenceID], skipped: [AlertOccurrenceID],
      failures: [NotificationIdentity: NotificationApplyFailure]
    ) {
      self.posted = posted
      self.skipped = skipped
      self.failures = failures
    }
  }

  /// Why a scheduler refused a plan or alerts, before touching the center.
  nonisolated public enum NotificationSchedulerError: Error, Hashable, Sendable {
    /// The plan or an alert belongs to another namespace.
    case namespaceMismatch(expected: String, found: String)
    /// An identity appears twice; one identifier holds one request.
    case duplicateIdentity(NotificationIdentity)
  }

  /// Installs notification plans as pending requests under stable identifiers, and reports what
  /// it confirmed.
  ///
  /// Each request's identifier is its alert's ``NotificationIdentity`` under
  /// ``identifierPrefix``, so a changed time or text replaces the request by adding it again,
  /// and only requests of this prefix and ``namespace`` are ever removed. Triggers are
  /// non-repeating calendar dates in UTC, so a change of the device's time zone doesn't move
  /// them.
  ///
  /// The scheduler is an update pump: calls run one batch at a time, and each `apply` makes
  /// its plan the latest. A batch stops before its next call to the center when a later plan
  /// has arrived, after finishing the call in flight, so the center always reconciles toward
  /// the latest plan. Nothing is atomic: a failed add or another writer leaves the center as
  /// it is until the next `apply`. Designate one scheduling process and one scheduler per
  /// namespace; extensions ask that owner to replan.
  ///
  /// RFC 0003 §4.5 defines the batch and the report.
  public actor NotificationScheduler {
    /// The prefix of every request identifier the scheduler writes.
    public nonisolated let identifierPrefix: String
    /// The namespace the scheduler owns.
    public nonisolated let namespace: String
    private let threadIdentifier: String?
    private let center: any AlertNotificationCenter
    private let deliveredRetention: Duration?
    private let now: @Sendable () -> Date

    private var generation = 0
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Creates a scheduler.
    ///
    /// - Parameters:
    ///   - identifierPrefix: The prefix of every request identifier, such as the app's bundle
    ///     identifier and a dot.
    ///   - namespace: The namespace it owns; plans and alerts of another are refused. Use a
    ///     valid namespace (``NotificationIdentity/isValidNamespace(_:)``): the scheduler
    ///     recognizes its own requests by parsing their identifiers, so with any other it never
    ///     removes a request and adds every request again on each `apply`.
    ///   - threadIdentifier: A thread the scheduler sets on every request, or `nil` to keep
    ///     the content's own.
    ///   - center: The notification center; the app's by default.
    ///   - deliveredRetention: How long delivered notifications of the namespace stay before
    ///     an `apply` removes them, or `nil` to leave them all. Two days by default; a negative
    ///     retention counts as zero.
    ///   - now: The scheduler's clock.
    public init(
      identifierPrefix: String, namespace: String, threadIdentifier: String? = nil,
      center: any AlertNotificationCenter = UNUserNotificationCenter.current(),
      deliveredRetention: Duration? = .seconds(2 * 86_400),
      now: @escaping @Sendable () -> Date = { Date() }
    ) {
      self.identifierPrefix = identifierPrefix
      self.namespace = namespace
      self.threadIdentifier = threadIdentifier
      self.center = center
      self.deliveredRetention = deliveredRetention
      self.now = now
    }

    /// How many plans `apply` has accepted, for tests that interleave calls.
    package var submittedApplies: Int { generation }

    /// How many calls wait for the pump, for tests that interleave calls.
    package var waitingCalls: Int { waiting.count }

    /// Installs `plan` and reads it back.
    ///
    /// The batch reads authorization, the pending requests and, with a retention, the
    /// delivered notifications; removes the owned requests the plan no longer wants (all of
    /// them when alerts aren't allowed) and the owned delivered notifications older than the
    /// retention; adds every alert after the batch's start whose request doesn't already
    /// match; and reads the pending requests back. A request matches when it has the same
    /// identifier, a calendar trigger for the same instant, and the same content.
    ///
    /// - Parameters:
    ///   - plan: The plan, of this scheduler's namespace.
    ///   - content: The content of an alert's notification. The scheduler only sets the thread.
    ///     It runs on the scheduler's actor, so build it from values the closure captured.
    /// - Returns: What the read-back confirmed.
    /// - Throws: ``NotificationSchedulerError``, before any call to the center, for a plan or
    ///   alert of another namespace or a repeated identity, including an empty plan of another
    ///   namespace.
    public func apply(
      _ plan: NotificationPlan,
      content: @Sendable (PlannedAlert) -> UNMutableNotificationContent
    ) async throws(NotificationSchedulerError) -> NotificationApplyReport {
      try validate(namespace: plan.namespace, alerts: plan.alerts)
      generation += 1
      let mine = generation
      await acquire()
      defer { release() }
      return await run(plan, generation: mine, content: content)
    }

    /// Posts alerts at once, unless the system will deliver them or already has.
    ///
    /// For apps that also run ``InProcessAlertEngine``: an alert the plan left out still gets a
    /// notification when it comes due. An alert whose request is still pending is skipped, as
    /// is one with a delivered notification dated no earlier than 1.5 seconds before its fire
    /// date. Each posted request has the alert's identifier and the scheduler's thread, as an
    /// `apply`'s does, and no trigger. It doesn't check that an alert is due: pass the alerts
    /// the engine reports. It waits for the calls that arrived before it, never supersedes an
    /// `apply`, and is never superseded.
    ///
    /// - Throws: ``NotificationSchedulerError`` for an alert of another namespace or a repeated
    ///   identity, before any call to the center.
    public func deliver(
      _ alerts: [PlannedAlert],
      content: @Sendable (PlannedAlert) -> UNMutableNotificationContent
    ) async throws(NotificationSchedulerError) -> NotificationDeliveryReport {
      try validate(namespace: namespace, alerts: alerts)
      await acquire()
      defer { release() }

      let ordered = alerts.sorted(by: PlannedAlert.precedes)
      var failures: [NotificationIdentity: NotificationApplyFailure] = [:]
      guard Self.allowsAlerts(await center.authorizationStatus()) else {
        for alert in ordered { failures[alert.id] = .notAuthorized }
        return NotificationDeliveryReport(posted: [], skipped: [], failures: failures)
      }
      let pending = Set(((try? await center.pendingNotificationRequests()) ?? []).map(\.identifier))
      let delivered = await center.deliveredNotificationRecords()
      var posted: [AlertOccurrenceID] = []
      var skipped: [AlertOccurrenceID] = []
      for alert in ordered {
        let identifier = alert.id.requestIdentifier(prefix: identifierPrefix)
        let earliest = alert.fireDate.addingTimeInterval(-CatchUpPolicy.earlyLeeway)
        if pending.contains(identifier)
          || delivered.contains(where: { $0.identifier == identifier && $0.date >= earliest })
        {
          skipped.append(alert.occurrenceID)
          continue
        }
        do {
          try await center.add(
            UNNotificationRequest(
              identifier: identifier, content: makeContent(alert, content), trigger: nil))
          posted.append(alert.occurrenceID)
        } catch {
          failures[alert.id] = .addFailed(error.localizedDescription)
        }
      }
      return NotificationDeliveryReport(posted: posted, skipped: skipped, failures: failures)
    }

    // MARK: The batch

    private func run(
      _ plan: NotificationPlan, generation mine: Int,
      content: @Sendable (PlannedAlert) -> UNMutableNotificationContent
    ) async -> NotificationApplyReport {
      var failures: [NotificationIdentity: NotificationApplyFailure] = [:]
      func superseded() -> NotificationApplyReport {
        NotificationApplyReport(
          verifiedAt: now(), confirmed: [], failures: failures, superseded: true,
          confirmedCoveredUntil: nil)
      }
      // A plan replaced while it waited makes no call; a batch stops before its next call.
      var isLatest: Bool { mine == generation }

      let start = now()
      let desired = plan.alerts.filter { $0.fireDate > start }
      let identifiers = desired.map { $0.id.requestIdentifier(prefix: identifierPrefix) }
      let requests = zip(desired, identifiers).map { alert, identifier in
        makeRequest(alert, identifier: identifier, content: content)
      }

      guard isLatest else { return superseded() }
      let allowed = Self.allowsAlerts(await center.authorizationStatus())
      guard isLatest else { return superseded() }
      // A read that fails leaves nothing known to be owned or matching.
      let pending = (try? await center.pendingNotificationRequests()) ?? []
      var owned: [String: UNNotificationRequest] = [:]
      for request in pending where owns(request.identifier) && owned[request.identifier] == nil {
        owned[request.identifier] = request
      }
      var delivered: [DeliveredNotificationRecord] = []
      if deliveredRetention != nil {
        guard isLatest else { return superseded() }
        delivered = await center.deliveredNotificationRecords()
      }

      let wanted = Set(identifiers)
      let obsolete = owned.keys.filter { !allowed || !wanted.contains($0) }.sorted()
      if !obsolete.isEmpty {
        guard isLatest else { return superseded() }
        await center.removePendingNotificationRequests(withIdentifiers: obsolete)
      }
      if let retention = deliveredRetention {
        // A negative retention counts as zero.
        let cutoff = start.addingTimeInterval(-max(0, retention.timeInterval))
        let expired = delivered.filter { owns($0.identifier) && $0.date < cutoff }
          .map(\.identifier).sorted()
        if !expired.isEmpty {
          guard isLatest else { return superseded() }
          await center.removeDeliveredNotifications(withIdentifiers: expired)
        }
      }

      if allowed {
        for (alert, request) in zip(desired, requests) {
          if let existing = owned[request.identifier], Self.matches(existing, request) { continue }
          guard isLatest else { return superseded() }
          do {
            try await center.add(request)
          } catch {
            failures[alert.id] = .addFailed(error.localizedDescription)
          }
        }
      } else {
        for alert in desired { failures[alert.id] = .notAuthorized }
      }

      guard isLatest else { return superseded() }
      let readBack = try? await center.pendingNotificationRequests()
      let verifiedAt = now()
      var found: [String: UNNotificationRequest] = [:]
      for request in readBack ?? [] where found[request.identifier] == nil {
        found[request.identifier] = request
      }
      var confirmed: [AlertOccurrenceID] = []
      var firstUnconfirmed: Date?
      for (alert, request) in zip(desired, requests) where alert.fireDate > verifiedAt {
        if allowed, let pending = found[request.identifier], Self.matches(pending, request) {
          confirmed.append(alert.occurrenceID)
          failures[alert.id] = nil
          continue
        }
        if failures[alert.id] == nil { failures[alert.id] = .unconfirmed }
        // The earliest, since a hand-made plan need not be sorted.
        firstUnconfirmed = min(firstUnconfirmed ?? alert.fireDate, alert.fireDate)
      }
      let covered = min(plan.coveredUntil, firstUnconfirmed ?? plan.coveredUntil)
      return NotificationApplyReport(
        verifiedAt: verifiedAt, confirmed: confirmed, failures: failures, superseded: false,
        confirmedCoveredUntil: readBack == nil ? nil : max(verifiedAt, covered))
    }

    // MARK: Requests

    private func owns(_ identifier: String) -> Bool {
      NotificationIdentity(requestIdentifier: identifier, prefix: identifierPrefix)?.namespace
        == namespace
    }

    private func makeContent(
      _ alert: PlannedAlert, _ content: @Sendable (PlannedAlert) -> UNMutableNotificationContent
    ) -> UNMutableNotificationContent {
      let body = content(alert)
      if let threadIdentifier { body.threadIdentifier = threadIdentifier }
      return body
    }

    private func makeRequest(
      _ alert: PlannedAlert, identifier: String,
      content: @Sendable (PlannedAlert) -> UNMutableNotificationContent
    ) -> UNNotificationRequest {
      UNNotificationRequest(
        identifier: identifier, content: makeContent(alert, content),
        trigger: Self.trigger(at: alert.fireDate))
    }

    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .gmt

    /// A non-repeating Gregorian calendar trigger in UTC at `date`, rounded up to a whole
    /// second, so it never fires before `date`. A thousandth of a second past a whole second
    /// counts as on it, so arithmetic noise doesn't add a second.
    static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
      let seconds = (date.timeIntervalSinceReferenceDate - 0.001).rounded(.up)
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = utc
      var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: Date(timeIntervalSinceReferenceDate: seconds))
      components.calendar = calendar
      components.timeZone = utc
      return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    /// The instant a calendar trigger names, in its own calendar and time zone.
    static func instant(of trigger: UNCalendarNotificationTrigger) -> Date? {
      var components = trigger.dateComponents
      var calendar = components.calendar ?? Calendar(identifier: .gregorian)
      calendar.timeZone = components.timeZone ?? components.calendar?.timeZone ?? .current
      components.calendar = nil
      components.timeZone = nil
      return calendar.date(from: components)
    }

    /// Whether a pending request matches the desired one: the same identifier, a non-repeating
    /// calendar trigger for the same instant, and the same content. Attachments aren't
    /// compared, because the system moves their files.
    static func matches(_ pending: UNNotificationRequest, _ desired: UNNotificationRequest) -> Bool
    {
      guard pending.identifier == desired.identifier,
        let found = pending.trigger as? UNCalendarNotificationTrigger, !found.repeats,
        let wanted = desired.trigger as? UNCalendarNotificationTrigger,
        let foundDate = instant(of: found), foundDate == instant(of: wanted)
      else { return false }
      let a = pending.content
      let b = desired.content
      return a.title == b.title && a.subtitle == b.subtitle && a.body == b.body
        && a.sound == b.sound && a.badge == b.badge && a.threadIdentifier == b.threadIdentifier
        && a.categoryIdentifier == b.categoryIdentifier
        && NSDictionary(dictionary: a.userInfo).isEqual(to: b.userInfo)
        && a.interruptionLevel == b.interruptionLevel && a.relevanceScore == b.relevanceScore
        && a.targetContentIdentifier == b.targetContentIdentifier
        && a.filterCriteria == b.filterCriteria
    }

    /// Whether authorization lets the app schedule alerts.
    static func allowsAlerts(_ status: UNAuthorizationStatus) -> Bool {
      switch status {
      case .authorized, .provisional: return true
      case .denied, .notDetermined: return false
      default:
        #if os(iOS) || os(visionOS)
          return status == .ephemeral
        #else
          return false
        #endif
      }
    }

    // MARK: Validation and the pump

    private func validate(
      namespace found: String, alerts: [PlannedAlert]
    ) throws(NotificationSchedulerError) {
      guard found == namespace else {
        throw .namespaceMismatch(expected: namespace, found: found)
      }
      for alert in alerts where alert.id.namespace != namespace {
        throw .namespaceMismatch(expected: namespace, found: alert.id.namespace)
      }
      var seen = Set<NotificationIdentity>()
      for alert in alerts where !seen.insert(alert.id).inserted {
        throw .duplicateIdentity(alert.id)
      }
    }

    /// Waits for the batch in progress; batches run one at a time, in the order they arrive.
    private func acquire() async {
      guard busy else {
        busy = true
        return
      }
      await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the pump to the next waiting call, or frees it.
    private func release() {
      if waiting.isEmpty {
        busy = false
      } else {
        waiting.removeFirst().resume()
      }
    }
  }

  nonisolated extension AlertSound {
    /// The notification sound for this alert sound: none, the default, or the named file. On
    /// watchOS, where named notification sounds aren't available, a named sound plays the
    /// default.
    public var notificationSound: UNNotificationSound? {
      switch self {
      case .none: return nil
      case .system: return .default
      case .named(let name):
        #if os(watchOS)
          return .default
        #else
          return UNNotificationSound(named: UNNotificationSoundName(name))
        #endif
      }
    }
  }
#endif
