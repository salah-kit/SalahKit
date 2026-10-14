#if canImport(UserNotifications) && !os(tvOS)
  import Foundation
  import SalahAlerts
  import UserNotifications

  /// A clock that tests set by hand, shared by a scheduler and a modelled center.
  nonisolated final class TestClock: @unchecked Sendable {
    // @unchecked: every access to `value` holds `lock`.
    private let lock = NSLock()
    private var value: Date

    init(_ date: Date) {
      value = date
    }

    var now: Date {
      lock.withLock { value }
    }

    func set(_ date: Date) {
      lock.withLock { value = date }
    }
  }

  /// The modelled notification center of `Vectors/README.md` (Reconciliation vectors).
  ///
  /// It keeps pending requests by identifier, replaces one on an add with the same identifier,
  /// delivers due requests when it's read, and logs every call. Adds can fail, be ignored or
  /// be dropped; reads can fail; one call can be held until the test releases it.
  ///
  /// A class with a lock rather than an actor: `UNNotificationRequest` isn't `Sendable`, so an
  /// actor's methods couldn't take or return it across the protocol's nonisolated requirements.
  nonisolated final class ModelCenter: AlertNotificationCenter, @unchecked Sendable {
    // @unchecked: every stored property is read and written while holding `lock`, and the
    // requests it holds are immutable once created.
    struct AddFailure: Error, CustomStringConvertible {
      var identifier: String
      var description: String { "The model center rejected \(identifier)." }
    }

    struct ReadFailure: Error {}

    private let lock = NSLock()
    private let clock: TestClock
    private var authorization: UNAuthorizationStatus
    private var pendingRequests: [String: UNNotificationRequest] = [:]
    private var deliveredRecords: [DeliveredNotificationRecord] = []
    private var failAdds: Set<String> = []
    private var ignoreAdds: Set<String> = []
    private var dropAdds: Set<String> = []
    private var failReads: Set<Int> = []
    private var log: [JSON] = []
    private var reads = 0
    private var stepReads = 0
    private var stepCalls = 0
    private var readBackAt: Date?
    private var suspendAtCall: Int?
    private var suspension: CheckedContinuation<Void, Never>?
    private var suspended = false

    init(
      clock: TestClock, authorization: UNAuthorizationStatus = .authorized,
      pending: [UNNotificationRequest] = [], delivered: [DeliveredNotificationRecord] = []
    ) {
      self.clock = clock
      self.authorization = authorization
      for request in pending { pendingRequests[request.identifier] = request }
      deliveredRecords = delivered
    }

    var pending: [String: UNNotificationRequest] { lock.withLock { pendingRequests } }
    var delivered: [DeliveredNotificationRecord] { lock.withLock { deliveredRecords } }
    var calls: [JSON] { lock.withLock { log } }
    var isSuspended: Bool { lock.withLock { suspended } }

    func configure(
      failAdds: Set<String>, ignoreAdds: Set<String>, dropAdds: Set<String>, failReads: Set<Int>
    ) {
      lock.withLock {
        self.failAdds = failAdds
        self.ignoreAdds = ignoreAdds
        self.dropAdds = dropAdds
        self.failReads = failReads
      }
    }

    func setAuthorization(_ status: UNAuthorizationStatus) {
      lock.withLock { authorization = status }
    }

    /// Starts a step: the read-back (the step's second pending read) moves the clock to
    /// `readBackAt`, and the step's `suspendAtCall`-th call waits for `release()`.
    func beginStep(readBackAt: Date?, suspendAtCall: Int? = nil) {
      lock.withLock {
        self.readBackAt = readBackAt
        self.suspendAtCall = suspendAtCall
        stepReads = 0
        stepCalls = 0
      }
    }

    func release() {
      let continuation = lock.withLock {
        suspended = false
        defer { suspension = nil }
        return suspension
      }
      continuation?.resume()
    }

    /// Counts a call, and holds it when it's the step's `suspendAtCall`-th.
    private func enter() async {
      let hold = lock.withLock {
        stepCalls += 1
        return stepCalls == suspendAtCall
      }
      guard hold else { return }
      await withCheckedContinuation { continuation in
        lock.withLock {
          suspension = continuation
          suspended = true
        }
      }
    }

    // MARK: AlertNotificationCenter

    func authorizationStatus() async -> UNAuthorizationStatus {
      await enter()
      return lock.withLock {
        log.append("authorizationStatus")
        return authorization
      }
    }

    func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
      await enter()
      let (requests, fails) = lock.withLock {
        log.append("pendingRequests")
        reads += 1
        stepReads += 1
        if stepReads == 2, let readBackAt { clock.set(readBackAt) }
        deliverDue()
        return (
          pendingRequests.values.sorted { $0.identifier < $1.identifier }, failReads.contains(reads)
        )
      }
      if fails { throw ReadFailure() }
      return requests
    }

    func add(_ request: UNNotificationRequest) async throws {
      await enter()
      let failed = lock.withLock { () -> Bool in
        if let fireDate = Self.fireDate(of: request) {
          log.append(
            .object([
              "add": .string(request.identifier), "fireDate": .string(Instant.text(fireDate)),
            ]))
        } else {
          log.append(.object(["addImmediate": .string(request.identifier)]))
        }
        if failAdds.contains(request.identifier) { return true }
        if ignoreAdds.contains(request.identifier) { return false }
        if dropAdds.contains(request.identifier) {
          pendingRequests[request.identifier] = nil
          return false
        }
        if request.trigger == nil {
          recordDelivery(request.identifier, at: clock.now)
        } else {
          pendingRequests[request.identifier] = request
        }
        return false
      }
      if failed { throw AddFailure(identifier: request.identifier) }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
      await enter()
      lock.withLock {
        log.append(.object(["removePending": .array(identifiers.map(JSON.string))]))
        for identifier in identifiers { pendingRequests[identifier] = nil }
      }
    }

    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
      await enter()
      return lock.withLock {
        log.append("deliveredNotifications")
        return deliveredRecords
      }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
      await enter()
      lock.withLock {
        log.append(.object(["removeDelivered": .array(identifiers.map(JSON.string))]))
        let removed = Set(identifiers)
        deliveredRecords.removeAll { removed.contains($0.identifier) }
      }
    }

    // MARK: Model (called while holding the lock)

    /// Delivers every pending request whose fire date has come, by fire date and identifier,
    /// dated at its fire date.
    private func deliverDue() {
      let now = clock.now
      let due = pendingRequests.values.compactMap { request in
        Self.fireDate(of: request).flatMap { $0 <= now ? (request.identifier, $0) : nil }
      }
      for (identifier, fireDate) in due.sorted(by: { ($0.1, $0.0) < ($1.1, $1.0) }) {
        pendingRequests[identifier] = nil
        recordDelivery(identifier, at: fireDate)
      }
    }

    /// A delivered notification replaces an older one with the same identifier.
    private func recordDelivery(_ identifier: String, at date: Date) {
      deliveredRecords.removeAll { $0.identifier == identifier }
      deliveredRecords.append(DeliveredNotificationRecord(identifier: identifier, date: date))
    }

    /// The instant a calendar trigger names, read in its components' time zone, else its
    /// calendar's, else the device's (RFC 0003 §4.5 Matching).
    static func fireDate(of request: UNNotificationRequest) -> Date? {
      guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
      var components = trigger.dateComponents
      var calendar = components.calendar ?? Calendar(identifier: .gregorian)
      calendar.timeZone = components.timeZone ?? components.calendar?.timeZone ?? .current
      components.calendar = nil
      components.timeZone = nil
      return calendar.date(from: components)
    }

    /// A request like the scheduler's: a non-repeating UTC calendar trigger and plain content.
    static func request(
      _ identifier: String, fireDate: Date, title: String, body: String, thread: String
    ) -> UNNotificationRequest {
      var calendar = Calendar(identifier: .gregorian)
      let utc = TimeZone(identifier: "UTC") ?? .current
      calendar.timeZone = utc
      var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: fireDate)
      components.calendar = calendar
      components.timeZone = utc
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.threadIdentifier = thread
      return UNNotificationRequest(
        identifier: identifier, content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
  }

  extension JSON: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
      self = .string(value)
    }
  }
#endif
