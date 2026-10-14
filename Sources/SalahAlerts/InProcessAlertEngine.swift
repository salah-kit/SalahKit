import Foundation
import SalahCore

/// How late the in-process engine still reports an alert, after sleep or a busy moment.
///
/// An at-time alert is caught up for ``atTimeGrace`` after its fire date, a reminder for
/// ``reminderGrace``, both inclusive; a before-reminder is never reported once its prayer has
/// begun. Negative values count as zero.
nonisolated public struct CatchUpPolicy: Hashable, Sendable {
  /// How long after its fire date an at-time alert is still due. Five minutes by default.
  public var atTimeGrace: Duration
  /// How long after its fire date a reminder is still due. Two minutes by default.
  public var reminderGrace: Duration

  /// Creates a policy.
  public init(
    atTimeGrace: Duration = .seconds(5 * 60), reminderGrace: Duration = .seconds(2 * 60)
  ) {
    self.atTimeGrace = atTimeGrace
    self.reminderGrace = reminderGrace
  }

  /// How early an alert already counts as due: a timer that fires a little early still
  /// reports it.
  static let earlyLeeway: TimeInterval = 1.5

  /// Whether `alert` is due at `now`.
  func isDue(_ alert: PlannedAlert, at now: Date) -> Bool {
    let lateness = now.timeIntervalSince(alert.fireDate)
    let grace = max(0, (alert.kind == .atTime ? atTimeGrace : reminderGrace).timeInterval)
    guard lateness >= -Self.earlyLeeway, lateness <= grace else { return false }
    // A before-reminder never fires once its prayer has begun.
    return alert.kind != .before || now < alert.event.time
  }

  /// How long the engine remembers a handled occurrence after its fire date: three hours, or
  /// longer than a longer grace.
  var retention: TimeInterval {
    max(3 * 3_600, atTimeGrace.timeInterval + 60, reminderGrace.timeInterval + 60)
  }
}

/// The in-process engine's time: the current instant, and one wake-up at a wall-clock date.
///
/// ``SystemAlertClock`` is the real one. Tests inject their own to move time by hand.
@MainActor public protocol AlertClock {
  /// The current instant.
  var now: Date { get }
  /// Calls `action` at `date` or a little after, replacing the wake-up armed before; `nil`
  /// disarms it.
  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void)
}

/// The real clock. A wake-up waits on the continuous clock with a tolerance of 0.75 seconds.
///
/// System sleep and clock changes can make it late or early; ``InProcessAlertEngine/resync(now:)``
/// covers both.
@MainActor public final class SystemAlertClock: AlertClock {
  private var task: Task<Void, Never>?

  /// Creates a clock.
  public init() {}

  /// The current instant.
  public var now: Date { Date() }

  /// Calls `action` at `date` or a little after, replacing the wake-up armed before.
  public func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    task?.cancel()
    task = nil
    guard let date else { return }
    let delay = max(0, date.timeIntervalSinceNow)
    task = Task { @MainActor in
      do {
        try await Task.sleep(
          for: .milliseconds(Int64((delay * 1_000).rounded(.up))),
          tolerance: .milliseconds(750))
      } catch {
        return
      }
      action()
    }
  }
}

/// Follows a complete ``AlertSchedule`` inside a running app and reports each alert when it
/// comes due, once.
///
/// It's for apps that keep running, such as a menu-bar app: it follows every alert, so
/// reminders a ``NotificationPlan`` leaves out still come due. Give it the schedule with
/// ``update(_:)``, and call ``resync(now:)`` when the device wakes, when the clock changes and
/// when the app becomes active. `onDue` gets the alerts that became due together, by fire date
/// and identity, whatever their sound: the app delivers and plays what it chooses, and
/// ``preferredAlert(among:)`` is the default for choosing one sound.
///
/// An alert is due from 1.5 seconds before its fire date until its grace ends
/// (``CatchUpPolicy``); a before-reminder never once its prayer has begun. The engine
/// remembers handled occurrences for three hours after their fire dates, in memory: an app
/// that must not repeat an alert across a relaunch keeps that record itself.
@MainActor public final class InProcessAlertEngine {
  private let catchUp: CatchUpPolicy
  private let clock: any AlertClock
  private let onDue: @MainActor ([PlannedAlert]) -> Void
  private var alerts: [PlannedAlert] = []
  /// Handled occurrences, kept until their fire date is older than the retention.
  private var handled: Set<AlertOccurrenceID> = []

  /// Creates an engine.
  ///
  /// - Parameters:
  ///   - catchUp: How late an alert is still reported.
  ///   - clock: The engine's time; the real clock by default.
  ///   - onDue: Called on the main actor with the alerts that became due together.
  public init(
    catchUp: CatchUpPolicy = CatchUpPolicy(), clock: any AlertClock = SystemAlertClock(),
    onDue: @escaping @MainActor ([PlannedAlert]) -> Void
  ) {
    self.catchUp = catchUp
    self.clock = clock
    self.onDue = onDue
  }

  /// Replaces the schedule and reports what is due at the clock's current instant.
  ///
  /// Include the catch-up interval in the schedule's range (`from: now − 5 minutes`), so an
  /// alert that came due just before a replan is still there.
  public func update(_ schedule: AlertSchedule) {
    alerts = schedule.alerts.sorted(by: PlannedAlert.precedes)
    check(at: clock.now)
  }

  /// Reports what is due at `now`, or at the clock's current instant, and re-arms the
  /// wake-up. Call it when the device wakes, when the clock changes and when the app becomes
  /// active.
  public func resync(now: Date? = nil) {
    check(at: now ?? clock.now)
  }

  /// The alert whose sound the engine's default precedence plays, among alerts due together.
  ///
  /// The latest fire date wins. At one instant an at-time alert beats a before-reminder,
  /// which beats an after-reminder; between two prayers' alerts of one kind, the later
  /// identity wins. Filter the alerts whose sound you play first.
  nonisolated public static func preferredAlert(
    among alerts: some Sequence<PlannedAlert>
  ) -> PlannedAlert? {
    alerts.max { lhs, rhs in
      if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
      if lhs.kind != rhs.kind { return lhs.kind > rhs.kind }
      return lhs.id < rhs.id
    }
  }

  private func check(at now: Date) {
    let horizon = now.addingTimeInterval(-catchUp.retention)
    handled = handled.filter { $0.fireDate >= horizon }
    let due = alerts.filter { !handled.contains($0.occurrenceID) && catchUp.isDue($0, at: now) }
    handled.formUnion(due.map(\.occurrenceID))

    let earliest = now.addingTimeInterval(CatchUpPolicy.earlyLeeway)
    if let next = alerts.first(where: {
      $0.fireDate > earliest && !handled.contains($0.occurrenceID)
    }) {
      clock.wake(at: next.fireDate.addingTimeInterval(0.15)) { [weak self] in
        guard let self else { return }
        self.check(at: self.clock.now)
      }
    } else {
      clock.wake(at: nil) {}
    }
    // Last, so an app that replans inside `onDue` finds the alerts already handled.
    if !due.isEmpty { onDue(due) }
  }
}
