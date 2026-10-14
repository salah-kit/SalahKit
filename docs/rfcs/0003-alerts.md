# RFC 0003: SalahAlerts

- **Status:** Draft for 0.2.0. Its first consumer, `CalculatedPhone`, schedules alerts through it; Salah and the MenuBar example adopt it next. Open until shipped apps report (STANDARD.md, Releases).
- **Products:** SalahAlerts.
- **Started:** 2026-10-14.
- **Supersedes:** the API sketch in the SalahKit proposal, §7.5.
- **Depends on:** RFC 0001 (SalahCore: owning days, coverage gaps and their kinds).

SalahAlerts turns a prayer schedule into alerts: the complete alert schedule an always-running app can follow, and the smaller set of requests an operating system can keep. This RFC fixes its API and behavior. The JSON vectors in `Vectors/alerts/` and `Vectors/reconciliation/` encode them.

References like "§7.5" point to the SalahKit proposal; "Core §4.6" points to RFC 0001.

---

## 1. Summary

An app chooses, per prayer, whether it wants an alert at the prayer's time, a reminder before it and a reminder after it. `AlertPlanner` turns those settings and a `PrayerSchedule` into an `AlertSchedule`: every enabled alert in a range, with no request cap, and the intervals where alerts can't be known because the source has a gap. From that schedule it plans a `NotificationPlan`: the alerts that fit an app-assigned request budget, chosen so that the next two days are complete, and the instant until which the plan is complete.

`NotificationScheduler` installs a plan through `UNUserNotificationCenter` under stable identifiers, reads the requests back, and reports only what it confirmed. `InProcessAlertEngine` follows the complete schedule inside a running app, catches up after sleep, and reports each due alert once.

Nothing is invented. A missing prayer time never becomes an alert, and it shortens the coverage the planner reports. A failed or unverified request shortens the coverage the scheduler reports.

## 2. Scope

In SalahAlerts 0.2:
- settings and identity (`AlertKind`, `AlertSound`, `AlertSettings`, `AlertSubject`, `NotificationIdentity`, `AlertOccurrenceID`, `PlannedAlert`);
- planning (`AlertPlanner`, `AlertSchedule`, `AlertGap`, `AlertBudget`, `NotificationPlan`, `AlertPlanningError`);
- installing requests (`NotificationScheduler`, `AlertNotificationCenter`, `NotificationApplyReport`, `NotificationDeliveryReport`, `NotificationApplyFailure`, `NotificationSchedulerError`);
- running alerts in process (`InProcessAlertEngine`, `CatchUpPolicy`, `AlertClock`, `SystemAlertClock`).

Not in SalahAlerts (§7.5 "Stays in apps"): asking for notification authorization, notification wording, sound files and security-scoped custom files, audio playback, which process owns a namespace, and when to replan or refresh in the background. The package ships no sounds and no adhan recordings.

Platforms: the planner, the identities and the engine are plain Swift and build on every platform SalahKit supports, Linux included. `NotificationScheduler` and the `AlertNotificationCenter` protocol need UserNotifications with notification content, so they exist where `UserNotifications` can be imported, except tvOS, where notifications carry no title, body or sound and delivered notifications can't be read.

## 3. Public API

Every value type is `nonisolated` and `Sendable`, as in SalahCore (Core §3). The scheduler is an actor; the engine is `@MainActor`.

```swift
import Foundation
import SalahCore

// MARK: Settings

nonisolated public enum AlertKind: String, Codable, Hashable, CaseIterable, Comparable, Sendable {
  case atTime, before, after            // Comparable in this order
}

/// Codable as "none", "system" or {"named": "file.caf"}.
nonisolated public enum AlertSound: Codable, Hashable, Sendable {
  case none, system
  case named(String)                    // the app supplies the file; platform limits apply
}

/// Codable with offsets in seconds: {"atTime": true, "before": 600, "after": null,
/// "sound": "system", "beforeSound": "none", "afterSound": {"named": "chime.caf"}}.
nonisolated public struct AlertSettings: Codable, Hashable, Sendable {
  public var atTime: Bool
  public var before: Duration?          // a positive offset, at most the planner's maximum
  public var after: Duration?
  public var sound: AlertSound
  public var beforeSound: AlertSound
  public var afterSound: AlertSound
  public init(atTime: Bool = true, before: Duration? = nil, after: Duration? = nil,
              sound: AlertSound = .system, beforeSound: AlertSound = .system,
              afterSound: AlertSound = .system)
}

/// What the settings are asked about: a prayer of an owning day, with its observance.
nonisolated public struct AlertSubject: Hashable, Sendable {
  public var scheduleDay: CivilDay
  public var prayer: PrayerKind
  public var observance: PrayerObservance
  public init(scheduleDay: CivilDay, prayer: PrayerKind, observance: PrayerObservance = .ordinary)
}

// MARK: Identity

/// A logical request: the same when its time, reminder offset or text changes.
nonisolated public struct NotificationIdentity: Codable, Hashable, Comparable, Sendable {
  public var namespace: String
  public var scheduleDay: CivilDay      // the event's owning day, even after midnight
  public var prayer: PrayerKind
  public var kind: AlertKind
  public init(namespace: String, scheduleDay: CivilDay, prayer: PrayerKind, kind: AlertKind)
  /// Not empty, and no "/".
  public static func isValidNamespace(_ namespace: String) -> Bool
  /// "<prefix><namespace>/<scheduleDay>/<prayer>/<kind>", e.g. "salah.prayers/2026-06-02/dhuhr/before".
  public func requestIdentifier(prefix: String) -> String
  public init?(requestIdentifier: String, prefix: String)
}

/// A concrete delivery: the logical request and its fire date.
nonisolated public struct AlertOccurrenceID: Codable, Hashable, Sendable {
  public var notification: NotificationIdentity
  public var fireDate: Date
  public init(notification: NotificationIdentity, fireDate: Date)
}

nonisolated public struct PlannedAlert: Hashable, Identifiable, Sendable {
  public var id: NotificationIdentity
  public var event: PrayerEvent
  public var kind: AlertKind { get }    // id.kind
  public var fireDate: Date
  public var sound: AlertSound
  public var occurrenceID: AlertOccurrenceID { get }
  public init(id: NotificationIdentity, event: PrayerEvent, fireDate: Date, sound: AlertSound)
}

// MARK: Planning

/// Fire dates at which alerts of one kind may be due but can't be known.
nonisolated public struct AlertGap: Hashable, Sendable {
  public var interval: DateInterval     // half-open: [start, end)
  public var kind: AlertKind
  public var day: CivilDay              // the owning day whose events are unknown
  public var prayers: Set<PrayerKind>   // the prayers whose alerts of `kind` may fall in it
  public var reason: ScheduleGapReason
  public init(interval: DateInterval, kind: AlertKind, day: CivilDay,
              prayers: Set<PrayerKind>, reason: ScheduleGapReason)
}

/// Every enabled, known alert in the requested range, without a request cap.
nonisolated public struct AlertSchedule: Hashable, Sendable {
  public var namespace: String          // kept even when there are no alerts
  public var alerts: [PlannedAlert]     // by fire date, then identity
  public var requestedRange: DateInterval   // half-open, after the query limit
  public var gaps: [AlertGap]
  public init(namespace: String, alerts: [PlannedAlert], requestedRange: DateInterval,
              gaps: [AlertGap])
}

nonisolated public struct AlertBudget: Hashable, Sendable {
  public var maxPending: Int            // the app's allowance for this namespace
  public var nearTermWindow: Duration
  public var horizon: Duration
  public init(maxPending: Int = 60, nearTermWindow: Duration = .seconds(2 * 86_400),
              horizon: Duration = .seconds(14 * 86_400))
}

nonisolated public struct NotificationPlan: Hashable, Sendable {
  public var namespace: String
  public var effectiveRange: DateInterval
  public var alerts: [PlannedAlert]     // the selected requests, by fire date, then identity
  /// Every enabled alert before this instant is in `alerts` and known.
  public var coveredUntil: Date
  public var coverageByKind: [AlertKind: Date]
  public init(namespace: String, effectiveRange: DateInterval, alerts: [PlannedAlert],
              coveredUntil: Date, coverageByKind: [AlertKind: Date])
}

nonisolated public enum AlertPlanningError: Error, Hashable, Sendable {
  case invalidNamespace(String)
  case invalidMaximumReminderOffset(Duration)        // negative or above 7 days
  case reminderOffsetOutOfRange(AlertSubject, AlertKind, Duration)
}

nonisolated public struct AlertPlanner: Sendable {
  /// The largest maximumReminderOffset the planner accepts: seven days.
  public static let reminderOffsetLimit: Duration
  public init()
  public func schedule(_ schedule: PrayerSchedule, namespace: String,
                       from start: Date, to end: Date,
                       maximumReminderOffset: Duration = .seconds(2 * 3600),
                       settings: (AlertSubject) -> AlertSettings?)
    throws(AlertPlanningError) -> AlertSchedule
  public func notificationPlan(_ schedule: AlertSchedule, from now: Date,
                               budget: AlertBudget = AlertBudget()) -> NotificationPlan
}

// MARK: In process

nonisolated public struct CatchUpPolicy: Hashable, Sendable {
  public var atTimeGrace: Duration      // default 5 minutes
  public var reminderGrace: Duration    // default 2 minutes
  public init(atTimeGrace: Duration = .seconds(5 * 60), reminderGrace: Duration = .seconds(2 * 60))
}

/// The engine's time: the current instant and one wake-up at a wall-clock date.
@MainActor public protocol AlertClock {
  var now: Date { get }
  /// Calls `action` at `date` or a little after, replacing the wake-up armed before;
  /// nil disarms.
  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void)
}

/// The real clock: wakes with a 0.75-second tolerance.
@MainActor public final class SystemAlertClock: AlertClock { public init() }

@MainActor public final class InProcessAlertEngine {
  public init(catchUp: CatchUpPolicy = CatchUpPolicy(), clock: any AlertClock = SystemAlertClock(),
              onDue: @escaping @MainActor ([PlannedAlert]) -> Void)
  public func update(_ schedule: AlertSchedule)
  /// Call on wake, on a clock change and on becoming active. nil uses the engine's clock.
  public func resync(now: Date? = nil)
  /// The default audio precedence: the latest fire date; at one instant at-time, then before,
  /// then after.
  nonisolated public static func preferredAlert(among alerts: some Sequence<PlannedAlert>)
    -> PlannedAlert?
}
```

On Apple platforms with UserNotifications, except tvOS:

```swift
import UserNotifications

/// What the scheduler reads from a delivered notification.
nonisolated public struct DeliveredNotificationRecord: Hashable, Sendable {
  public var identifier: String
  public var date: Date
  public init(identifier: String, date: Date)
}

/// The part of UNUserNotificationCenter the scheduler uses; tests inject failures through it.
nonisolated public protocol AlertNotificationCenter: AnyObject, Sendable {
  func authorizationStatus() async -> UNAuthorizationStatus
  func pendingNotificationRequests() async throws -> [UNNotificationRequest]
  func add(_ request: UNNotificationRequest) async throws
  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord]
  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
}
/// authorizationStatus() and deliveredNotificationRecords() adapt notificationSettings() and
/// deliveredNotifications(); the other requirements are the center's own methods.
extension UNUserNotificationCenter: AlertNotificationCenter

nonisolated public enum NotificationApplyFailure: Hashable, Sendable {
  case notAuthorized          // authorization doesn't allow alerts; nothing was added
  case addFailed(String)      // the center rejected the request (the error's description)
  case unconfirmed            // read-back found no matching request
}

nonisolated public struct NotificationApplyReport: Hashable, Sendable {
  public var verifiedAt: Date
  public var confirmed: [AlertOccurrenceID]
  public var failures: [NotificationIdentity: NotificationApplyFailure]
  public var superseded: Bool
  /// Recomputed from matching pending requests; nil when read-back can't establish it.
  public var confirmedCoveredUntil: Date?
}

nonisolated public struct NotificationDeliveryReport: Hashable, Sendable {
  public var posted: [AlertOccurrenceID]
  public var skipped: [AlertOccurrenceID]
  public var failures: [NotificationIdentity: NotificationApplyFailure]
}

nonisolated public enum NotificationSchedulerError: Error, Hashable, Sendable {
  case namespaceMismatch(expected: String, found: String)
  case duplicateIdentity(NotificationIdentity)
}

/// One owner per namespace, with a serialized update pump.
public actor NotificationScheduler {
  public init(identifierPrefix: String, namespace: String, threadIdentifier: String? = nil,
              center: any AlertNotificationCenter = UNUserNotificationCenter.current(),
              deliveredRetention: Duration? = .seconds(2 * 86_400),
              now: @escaping @Sendable () -> Date = { Date() })
  public nonisolated let identifierPrefix: String
  public nonisolated let namespace: String
  public func apply(_ plan: NotificationPlan,
                    content: @Sendable (PlannedAlert) -> UNMutableNotificationContent)
    async throws(NotificationSchedulerError) -> NotificationApplyReport
  /// Posts due alerts the system won't deliver by itself.
  public func deliver(_ alerts: [PlannedAlert],
                      content: @Sendable (PlannedAlert) -> UNMutableNotificationContent)
    async throws(NotificationSchedulerError) -> NotificationDeliveryReport
}

nonisolated extension AlertSound {
  /// nil for .none, .default for .system, the named sound for .named (.default on watchOS).
  public var notificationSound: UNNotificationSound? { get }
}
```

## 4. Behavior

### 4.1 Settings and subjects

`AlertSettings` says which alerts a prayer gets: `atTime` at the event's instant, `before` at `time − before`, `after` at `time + after`. Each kind has its own sound. Offsets are elapsed time, unaffected by clock changes, like iqama's `.after` rule (Core §4.5).

The planner asks for settings per `AlertSubject`: the owning day, the prayer (any `PrayerKind`, sunrise included, so an app can offer a sunrise alert) and the observance. `nil` means no alerts for that subject. A subject is what both a known event and a source gap can supply: an event gives its own day, kind and observance; a gap gives its day and each kind it holds. A gap on a Friday's Dhuhr can't say whether the source would have declared Jumu'ah, so the planner asks for both observances (§4.3 Gaps). Settings may depend on the day, which is how an app gives Ramadan or a single date its own alerts, and on the observance, which is how Jumu'ah gets its own.

**JSON.** `AlertSettings` encodes offsets as seconds. Every key is optional when decoding, with the initializer's defaults (`atTime` true, no reminders, `"system"` sounds). An offset must be a finite number; a larger one is clamped to the date limit, as `StatePolicy` does (Core §3). Decoding doesn't check the offset's range: the planner does, against the maximum it's given. `AlertSound` encodes as `"none"`, `"system"` or `{"named": "<file>"}`.

### 4.2 Identity

A `NotificationIdentity` is the namespace, the owning day, the prayer and the alert kind. It excludes the fire date, the calculation settings, the reminder offset and the text, so moving a reminder across midnight, changing a calculation or rewording an alert keeps the same identity (§7.5 "Identity and updates"). The owning day is the event's `scheduleDay` (Core §4.3): Monday's Isha at 00:15 on Tuesday, and its reminders, belong to Monday; a calculated Fajr at 23:45, and its at-time alert before midnight, belong to the next day.

**Namespaces.** A namespace is a non-empty string without `/`. The planner rejects any other namespace (§4.3), and the scheduler only ever writes and removes requests of its own (§4.5).

**Request identifiers.** `requestIdentifier(prefix:)` is `prefix + namespace + "/" + scheduleDay + "/" + prayer + "/" + kind`, with the day as `YYYY-MM-DD` and the raw values of `PrayerKind` and `AlertKind`: `salah.prayers/2026-06-02/dhuhr/before`. `init?(requestIdentifier:prefix:)` reverses it: the identifier must start with the prefix, and the rest must be exactly four `/`-separated parts, a valid namespace, a valid `CivilDay`, a `PrayerKind` and an `AlertKind`. Anything else is `nil`, so a request in that form belongs to a scheduler exactly when it parses with the scheduler's prefix and its namespace matches.

**Occurrences.** `AlertOccurrenceID` adds the fire date. When a time changes, the identity stays and the occurrence changes, so the in-process engine can tell a new occurrence from one it has handled (§7.5).

**Order.** Identities are ordered by namespace, then owning day, then prayer in canonical order (Core §3), then alert kind (`atTime`, `before`, `after`). Alerts are ordered by fire date, then identity. This is the "canonical logical identifier" that breaks equal-time ties everywhere below. At one instant, an owning day's alerts come before the next day's: in Kazan, 19 June's Isha and 20 June's Fajr fall at 23:45, and the Isha alert comes first.

### 4.3 The alert schedule

`schedule(_:namespace:from:to:maximumReminderOffset:settings:)` builds the complete, uncapped schedule of the fire-date range `[start, end)`. An end before the start counts as the start.

**Errors**, checked in this order, the first that applies thrown:
1. `invalidNamespace` when the namespace isn't valid (§4.2);
2. `invalidMaximumReminderOffset` when `maximumReminderOffset` is negative or longer than `AlertPlanner.reminderOffsetLimit` (seven days);
3. `reminderOffsetOutOfRange(subject, kind, offset)` when the settings for a subject give a `before` or `after` offset that isn't positive or is longer than `maximumReminderOffset`. Subjects are asked in this order: the known events of the query in events order (Core §4.6), then the gaps (§4.3 Gaps) in order of their source gaps, by kind in canonical order, `.ordinary` before `.jumuah`. The first bad offset is thrown, `before` before `after`.

**Candidates.** Let `m` be `maximumReminderOffset`. The planner reads `schedule.events(from: start − m, through: end + m)` once. That query covers every event whose alerts can fire in `[start, end)`: after-reminders of earlier prayers and before-reminders of later ones (§7.5 "The budget and coverage"). For each known event, in events order, it asks for the settings of the event's subject and makes:
- an `atTime` alert at `time`, when `atTime` is on, with `sound`;
- a `before` alert at `time − before`, when `before` is set, with `beforeSound`;
- an `after` alert at `time + after`, when `after` is set, with `afterSound`.

It keeps the alerts whose fire date is in `[start, end)` and sorts them by fire date, then identity. The query's own limit (Core §4.10) can end the events before `end + m`; then the requested range ends `m` before the query's end, and `requestedRange` shows the shorter range, as `coverage.requested` does in Core.

**Gaps.** Every gap of the query's coverage (Core §4.6) is an interval `[lo, hi)` in which events of its `kinds`, owned by its `day`, may occur unknown. For each kind `k` in the gap, in canonical order, and each observance the subject can have (`.ordinary`; and `.jumuah` too when `k` is Dhuhr and the day is a Friday), the planner asks for the settings of `AlertSubject(scheduleDay: day, prayer: k, observance:)`. Each enabled alert kind moves the interval by its own offset:
- `atTime`: `[lo, hi)`;
- `before` with offset `b`: `[lo − b, hi − b)`;
- `after` with offset `a`: `[lo + a, hi + a)`.

Each interval is clipped to the requested range; empty ones are dropped. Intervals with the same bounds, kind, day and reason form one `AlertGap`, whose `prayers` are their prayers. Gaps are ordered by start, then day, then kind, then reason in declaration order (Core §4.6), then end. A gap of a prayer whose settings are `nil`, or enable nothing, makes no alert gap: missing data for a prayer the app doesn't alert never shortens its coverage. An unknown Isha makes the Isha before-reminder unknown `b` earlier than the Isha alert itself (§7.5: "an unknown future prayer can make its before-reminder unknown sooner").

### 4.4 The notification plan

`notificationPlan(_:from: now, budget:)` selects the requests for an operating system that keeps a limited number, and says how far the selection is complete (§7.5). Negative budget values count as zero.

**Effective range.** `[now, E)` with `E = max(now, min(requestedRange.end, now + horizon))`. Only alerts with a fire date in it can be selected. A requested range that ends at or before `now` gives an empty effective range and an empty plan. The near-term window is `[now, N)` with `N = min(now + nearTermWindow, E)`, so a window longer than the horizon can't extend the plan.

**Selection.**
1. **Near term.** Every alert with a fire date in `[now, N)`, of every kind, is reserved in order. If they number more than `maxPending`, the first `maxPending` are kept and nothing else is selected. Equal fire dates are ordered by identity, so no rule moves an earlier alert out for a later one.
2. **At-time fill.** With the capacity left, the `atTime` alerts with a fire date in `[N, E)` are selected, nearest first. Later reminders are never selected: they stay in the `AlertSchedule` for the in-process engine.

The plan's `alerts` are the selected alerts, by fire date, then identity.

**Coverage.** A kind is in `coverageByKind` when the schedule has an alert or a gap of that kind. For each such kind `K`, its cutoff is the earliest of:
- `E`;
- the fire date of the first alert of kind `K` with a fire date in `[now, E)` that wasn't selected;
- for each gap of kind `K` that meets `[now, E)` (`start < E` and `end > now`), `max(now, start)`. A gap entirely before `now` changes nothing, and a gap that contains `now` gives `now`.

When the requested range starts after `now`, nothing is known before its start, so every cutoff is `now`. `coveredUntil` is the earliest cutoff of any kind, or `E` when no kind is present (and `now` when the range starts after `now`). It is the end of a contiguous interval, from `now`, in which every enabled alert is known and selected; it is not the last selected alert's fire date. Each kind's cutoff uses its own offsets, so an unknown future prayer that hides a before-reminder doesn't shorten the at-time coverage.

**The arithmetic example (§7.5, D7).** Five prayers a day, each with an at-time alert, a before-reminder and an after-reminder, no reminder crossing a window edge, `now` at the start of a day, the default budget and a range of 14 days: the two near-term days reserve 30 requests, and the 30 left go to the at-time alerts of the next six days. The plan holds eight days of at-time alerts and two days of reminders; `coveredUntil` is the third day's first before-reminder; `coverageByKind[.atTime]` is the ninth day's first at-time alert.

### 4.5 The notification scheduler

A `NotificationScheduler` owns one namespace under one identifier prefix. The app designates one scheduling process and one scheduler per namespace; extensions ask that owner to replan rather than writing the namespace themselves. Different namespaces still share the app's operating-system capacity, and a process-local actor can't coordinate several processes (§7.5).

**Validation.** `apply` and `deliver` first check that the plan's namespace, and every alert's identity's namespace, equal the scheduler's, and that no identity appears twice: one identifier holds one request. Otherwise they throw `namespaceMismatch` or `duplicateIdentity` before any call to the center, including for an empty plan. A planner's plan never repeats an identity; a hand-made one might.

**The update pump.** Calls run one batch at a time, in the order they arrive, across suspension points; actor isolation alone would let two batches interleave. Every `apply` makes its plan the latest one. A batch checks, before each call to the center, whether a later `apply` has arrived; if so it stops, and its report says `superseded`. A call already made always finishes first, and nothing undoes an accepted add. An `apply` that is superseded before its batch starts makes no call at all. So the pump always reconciles toward the latest plan. `deliver` never supersedes an `apply` and isn't superseded.

**An `apply` batch.** With `t` the scheduler's `now` when the batch starts, the desired alerts are the plan's alerts with a fire date after `t`. The scheduler reads its clock at the start of a batch and after the read-back. The calls, in this order:
1. `authorizationStatus()`. Alerts are allowed when it is `.authorized`, `.provisional` or `.ephemeral`.
2. `pendingNotificationRequests()`. The owned requests are those whose identifiers parse with the scheduler's prefix and have its namespace (§4.2). If this read throws, nothing is owned and nothing matches.
3. `deliveredNotificationRecords()`, unless `deliveredRetention` is `nil`.
4. `removePendingNotificationRequests(withIdentifiers:)` with the obsolete owned requests, sorted, if there are any. Obsolete means every owned request when alerts aren't allowed, and otherwise every owned request whose identifier no desired alert has. A request that keeps its identity is never removed: a moved reminder is replaced, not removed and re-added.
5. `removeDeliveredNotifications(withIdentifiers:)` with the owned delivered notifications whose date is before `t − deliveredRetention`, sorted, if there are any. Other prefixes, other namespaces and newer notifications stay.
6. When alerts are allowed, `add(_:)` for each desired alert, in plan order, unless an owned pending request with its identifier already matches it (below). Adding under an existing identifier replaces the pending request, as Apple documents ([`UNNotificationRequest.identifier`](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier)). A thrown error becomes `addFailed` with the error's description.
7. `pendingNotificationRequests()` again: the read-back. `verifiedAt` is the scheduler's `now` after it.

Removing the obsolete requests before adding gives the new ones the room. Nothing in the batch is atomic or gap-free: a failed add, a superseded batch or another writer leaves the center as it is, and the next `apply` reconciles again (§7.5). There is no rollback.

**Requests.** A desired alert's request has its identity's identifier, a non-repeating `UNCalendarNotificationTrigger` with the year, month, day, hour, minute and second of its fire date, rounded up to a whole second, in a Gregorian calendar in UTC (§7.5 "Housekeeping": triggers don't move with the device's time zone), and the content the `content` closure returns for it. When the scheduler has a `threadIdentifier`, it sets the content's thread to it. The closure decides everything else, including the sound (`AlertSound.notificationSound` maps the alert's sound), the interruption level and the relevance score (§7.5 "Interruption levels").

**Matching.** A pending request matches a desired one when its identifier is the same, its trigger is a non-repeating calendar trigger for the same instant, and its content has the same title, subtitle, body, sound, badge, thread, category, user info, interruption level, relevance score, target content identifier and filter criteria. Attachments aren't compared: the system moves their files.

**The report.**
- When alerts aren't allowed, every desired alert fails with `notAuthorized`. Otherwise an alert whose add threw fails with `addFailed`.
- After the read-back, a desired alert whose fire date is after `verifiedAt` is **confirmed** when the read-back holds a matching request, and then has no failure. Otherwise, if it has no failure yet, it fails with `unconfirmed`: its request is missing, an older one with the same identifier is still there, or the read-back failed and confirms nothing.
- A desired alert whose fire date has passed by `verifiedAt` is never confirmed or `unconfirmed`: the read-back can't tell a delivered request from a lost one.

`confirmed` lists occurrences in plan order. `confirmedCoveredUntil` is `max(verifiedAt, min(plan.coveredUntil, u))`, where `u` is the fire date of the first desired alert after `verifiedAt` that isn't confirmed. A failed read-back makes `confirmed` empty and `confirmedCoveredUntil` nil. A superseded batch reports `superseded`, the failures it saw, an empty `confirmed`, a nil `confirmedCoveredUntil`, and the instant it stopped as `verifiedAt`. So the report never claims more than the read-back showed, and a failure always shortens `confirmedCoveredUntil` when it falls within the plan's coverage. Neither field proves that a notification was presented or heard (§7.5).

**Delivering due alerts.** `deliver(_:content:)` is for apps that also run the in-process engine: an alert the plan left out (a later reminder) still deserves a banner when it comes due. In the pump's order, it calls `authorizationStatus()`; if alerts aren't allowed, every alert fails with `notAuthorized`. Otherwise it reads the pending requests and the delivered notifications, then for each alert, by fire date and identity: an alert with a pending request under its identifier is **skipped** (the system will deliver it); so is an alert with a delivered notification under its identifier dated no earlier than 1.5 seconds before its fire date (this occurrence was delivered); every other alert is posted at once, with no trigger, and is **posted** or fails with `addFailed`. `posted` and `skipped` list occurrences in that order.

**Authorization** is the app's to request (§7.5 "Stays in apps"). The scheduler never asks; the protocol has no way to.

### 4.6 The in-process engine

`InProcessAlertEngine` is for apps that keep running, such as a menu-bar app. It follows the complete `AlertSchedule`, so reminders the notification plan leaves out still come due (§7.5).

- `update(_:)` replaces the schedule and checks for due alerts at the clock's `now`.
- `resync(now:)` checks for due alerts at `now`, or at the clock's `now` when it's nil. Apps call it when the device wakes, when the clock changes and when the app becomes active.
- After each check, the engine arms one wake-up at the fire date of the next alert that isn't due yet, plus 0.15 seconds, and checks again when it fires. `SystemAlertClock` wakes with a tolerance of 0.75 seconds. Sleep and clock changes can make any timer late or early; `resync` covers both.

**Due.** At `now`, an alert that hasn't been handled is due when `now − fireDate` lies in `[−1.5 s, grace]`, where the grace is `atTimeGrace` for an at-time alert and `reminderGrace` for a reminder (negative values count as zero), and, for a before-reminder, `now` is before its prayer's time. So an alert up to 1.5 seconds ahead counts as due, an at-time alert is caught up for 5 minutes by default and a reminder for 2, and a before-reminder never fires once its prayer has begun (§7.5 "Catch-up"). An alert past its grace is dropped silently.

**Once.** Each due alert is handled once: the engine remembers its `AlertOccurrenceID` and calls `onDue` with every alert that became due in that check, by fire date and identity. Repeated updates and wake checks don't repeat it. A changed fire date is a new occurrence. The engine forgets an occurrence three hours after its fire date (longer when a grace is longer), so the memory stays small; it isn't persisted, and keeping handled alerts across a relaunch is the app's policy (§7.5 "Deduplication").

**Audio.** `onDue` gets every due alert, whatever its sound; the app plays what it plays. `preferredAlert(among:)` is the documented default precedence for one sound among alerts due together: the latest fire date wins; at one instant `atTime` beats `before`, which beats `after`; and between two prayers' alerts of one kind at one instant, the later identity wins (Kazan's 20 June Fajr over 19 June's Isha). Apps first filter the alerts whose sound they play (§7.5 "Audio precedence").

An in-process caller includes its catch-up interval in the requested range: `schedule(…, from: now − 5 minutes, …)`.

### 4.7 Isolation and cost

The planner is a pure function of its inputs: it reads the schedule once, over the requested range plus `maximumReminderOffset` on each side, and never searches further. Every value type compiles under both default-isolation settings. `NotificationScheduler` is an actor and runs the content closure on its own executor, so the closure must be `@Sendable` and build its content from values it captured. `InProcessAlertEngine` and `AlertClock` are `@MainActor`, and `onDue` runs on the main actor.

## 5. Changes from the proposal's sketch

| Change | Why |
|---|---|
| `settings` takes an `AlertSubject` (day, prayer, observance), not a `PrayerEvent` | A source gap has no event, but §7.5 transforms it with the settings of the prayer it hides; a gap in a prayer whose alerts are off must not shorten coverage. A subject is what a gap can supply. Settings can still depend on the day and on Jumu'ah. |
| `AlertSchedule.gaps: [AlertGap]` replaces `coverage: ScheduleCoverage` | Each alert kind moves a gap by its own offset, and `coverageByKind` needs to know which kind a gap belongs to. A `ScheduleCoverage` holds prayer kinds, not alert kinds, and SalahCore 0.1 has no public initializer for it (Core §9 #9). |
| `from:to:` with a half-open range, instead of `from:through:` | §7.5 defines the effective range as half-open. In Swift, `to` excludes the end (`stride(from:to:by:)`) and `through` includes it, as in Core's `events(from:through:)`. |
| `AlertPlanner.reminderOffsetLimit` and `AlertPlanningError` | The sketch throws without saying what. A maximum offset beyond seven days would only widen the query; an offset outside the declared bound is rejected (§7.5). |
| `NotificationIdentity` builds and parses request identifiers; namespaces can't contain `/` | The scheduler removes only requests of its prefix and namespace, so ownership must be decidable from the identifier alone. An app also needs the identity of a notification the user tapped. |
| `NotificationScheduler.init` takes the center, a delivered-notification retention and a clock; `threadIdentifier` is optional | Tests inject failures through `AlertNotificationCenter` (§7.5 "Done means"); retention is configurable (§7.5 "Housekeeping"); a nil thread leaves the content's own. |
| `apply` throws `NotificationSchedulerError` | Namespace validation happens before any mutation; a typed error says so without a report that looks like a scheduling result. |
| `NotificationApplyReport.failures` holds `NotificationApplyFailure`, not `String` | An app and a test can tell "not allowed" from "rejected" from "not there on read-back". |
| `deliver(_:content:)` and `NotificationDeliveryReport` | An always-running app posts due alerts the plan left out. Posting them through the namespace's one owner keeps the "one writer per namespace" rule, and the scheduler can skip an occurrence the system already delivered or will deliver (Salah's catch-up, A2's `catchUpWindows`). |
| `AlertClock`, `SystemAlertClock`, and `resync(now: Date? = nil)` | The engine's timer and its checks use one clock that tests can inject (§7.5 "Done means": sleep, wake and clock changes). A default of `.now` would bypass an injected clock. |
| `InProcessAlertEngine.preferredAlert(among:)` | §7.5 makes the tested audio precedence the engine's documented default; apps play the sound themselves through `onDue`. |
| Public memberwise initializers on the value types | An app can test its own alert code with hand-made schedules and plans, and can install a plan it built without the planner. The scheduler validates whatever it gets. |

## 6. Behavior retained and corrected

A2 characterized Salah's `PrayerAlertScheduler` (Salah `a0206dd`, `GuidanceTests/PrayerAlertSchedulerCharacterizationTests.swift`). Each of its tests maps to SalahAlerts as follows.

| A2's test | Kind | In SalahAlerts |
|---|---|---|
| `characterizesTheAlertWindowIsYesterdayTodayAndTomorrow` | defect | Plans cover a horizon (14 days by default) within a budget, not three days (§4.4). |
| `alertWindowDaysAreCivilDaysInThePrayerZone` | retained | Identities use owning days in the location's zone (§4.2). |
| `characterizesTheThreeDayWindowNeverReachesTheCap`, `characterizesFirstSixtyRequestsByFireDateWithoutKindPriority` | defect | Near-term reservation, then at-time fill (§4.4, D7). |
| `schedulesEveryEnabledAlertStillAheadInTheWindow` | retained | The plan holds every enabled future alert that fits, in fire order. |
| `catchUpWindows` (14 cases) | retained | Engine catch-up (§4.6); `deliver` posts caught-up alerts that have no request (§4.5). |
| `characterizesIdentifiersCarryTheFireTimestamp` | defect | Stable identities without a timestamp (§4.2). |
| `requestContentPerKind` | retained | Content, including Salah's interruption levels and relevance, comes from the app's closure unchanged; the scheduler only sets the thread (§4.5). |
| `silentModeSchedulesSilentRequests` | app policy | The closure chooses the sound; `AlertSound.none` maps to no sound. |
| `triggersAreNonRepeatingUTCCalendarDates` | retained | §4.5 Requests. |
| `launchHousekeepingRemovesOnlyOldOwnDeliveredNotifications` | retained | Retention of delivered notifications, limited to the owned prefix and namespace (§4.5 step 5). |
| `rescheduleRemovesOwnDeliveredNotificationsThatNoLongerMatch` | changed | A plan holds only upcoming alerts, so the scheduler can't tell what a delivered notification "should" say now; delivered notifications stay until their retention ends. Removing one because its prayer moved would also erase the record that it was delivered. |
| `characterizesAMovedAlertIsRemovedBeforeItsReplacementIsAdded` | defect | A moved alert keeps its identifier and is replaced by an add, never removed first (§4.5 step 4). |
| `obsoleteOwnRequestsAreRemovedAndOthersKept` | retained | §4.5 step 4; other apps' requests stay. |
| `emptyScheduleClearsOwnRequestsAndDeliveries` | retained, changed | An empty plan removes every owned pending request; delivered notifications follow their retention (above). |
| `deniedAuthorizationRemovesOwnRequestsAndAddsNone` | retained | §4.5 step 4: when alerts aren't allowed every owned request is obsolete and nothing is added. |
| `authorizationIsRequestedOnlyWithSomethingToSchedule` | app policy | The scheduler never requests authorization. |
| `latestDueAlertPlays`, `adhanBeatsABeforeReminderAtTheSameInstant`, `beforeReminderBeatsAnAfterReminderAtTheSameInstant` | retained | `preferredAlert(among:)` (§4.6). |
| `duaFollowsOnlyTheAdhan` | app policy | Audio playback stays in apps. |
| `systemSoundsAndSilentModePlayNoAppAudio` | retained | `onDue` reports every due alert with its sound; the app plays only its own. |
| `aHandledAlertIsNotRepeated` | retained | §4.6 Once. |
| `armsTheAlertTimerJustAfterTheNextAlert` | retained | §4.6: the wake-up at the next fire date plus 0.15 s, 0.75 s tolerance. |

## 7. Vectors

`Vectors/README.md` documents the schema of `Vectors/alerts/` and `Vectors/reconciliation/`. Alert vectors run the planner on a `TimetableSource` or a `CalculationSource`; reconciliation vectors run the scheduler against a modelled notification center and assert what it holds afterwards, not what was requested. The expectations come from this RFC and §7.5, through a generator that models §4.3–§4.5 independently of the Swift implementation.

**Review before implementation** (2026-10-14). A fresh reviewer recomputed every vector with its own model of §7.5, this RFC and RFC 0001 §4.6, and found no wrong expectation. It found two vectors that proved less than they claimed (the query's reach to `start − m` and `end + m` was never observable; negative budget values other than the horizon were never exercised), a failed read-back that this section left ambiguous, and a center model that didn't say how a delivered notification with a repeated identifier is kept. The fixes added the vectors `after-reminder-from-the-query-start`, `before-reminder-from-near-the-query-end`, `negative-max-pending-counts-as-zero` and `negative-near-term-window-counts-as-zero`; the read-back rule above (every alert unconfirmed); the README's center rules; and, from its minor findings, vectors for a fractional fire date, a superseded batch's failures, a Jumu'ah gap subject and a repeated identity, which `Validation` now rejects.

## 8. Evidence

To be completed with the implementation: the vectors, the characterization ports, the scheduler and engine tests, and CalculatedPhone's journey on an iPhone simulator, which accepts the permission through Springboard, schedules alerts a minute or two ahead, terminates the app, observes delivery, and reads the pending requests back after a time change and an injected failure.

## 9. Open questions

1. **Persisting handled occurrences.** The engine's handled set lives in memory. An app relaunched within an alert's grace replays it. Whether the engine should accept a handled set to restore waits for a consumer that needs it.
2. **Several processes, one namespace.** Only one process may write a namespace. A widget extension or a notification service extension that needs alerts changed asks the app (§7.5).

## 10. Changes after review

None yet.
