# Alerts within the 64-notification limit

Plan two weeks of prayer alerts, keep the ones the system can hold, and know exactly how far
they reach.

## Overview

iOS keeps only a limited number of pending notification requests per app: 64, the soonest
ones, and it drops the rest. Five prayers with a reminder before and after each are fifteen
alerts a day, so four days fill the limit, and an app that isn't opened for a week goes quiet.

SalahAlerts plans every alert of the range you ask for, then spends a budget you choose: every
alert of the next two days first, then the prayer-time alerts of the days after, nearest first. With the default budget of 60, that's two
complete days and six more days of prayer-time alerts. The plan says until when it's complete,
so your app can say so too.

### Choose the alerts

Settings are asked per subject: a prayer of an owning day, with its observance. Return `nil`
for no alerts.

```swift
let settings: (AlertSubject) -> AlertSettings? = { subject in
  switch subject.prayer {
  case .sunrise: return nil
  case .fajr: return AlertSettings(before: .seconds(30 * 60))
  default: return AlertSettings(before: .seconds(10 * 60))
  }
}
```

An ``AlertSettings`` value turns on an alert at the prayer's time (on by default), a reminder
before it and a reminder after it, each with its own ``AlertSound``. A subject can be a Jumu'ah,
when your source declares one, so Friday's prayer can have its own:

```swift
let withJumuah: (AlertSubject) -> AlertSettings? = { subject in
  if subject.observance == .jumuah {
    return AlertSettings(before: .seconds(45 * 60), sound: .named("jumuah.caf"))
  }
  return settings(subject)
}
```

### Plan the schedule

``AlertPlanner/schedule(_:namespace:from:to:maximumReminderOffset:settings:)`` builds every
alert of a range; ``AlertPlanner/notificationPlan(_:from:budget:)`` selects the requests.

```swift
let planner = AlertPlanner()
let alerts = try planner.schedule(
  schedule, namespace: "prayers", from: now, to: now.addingTimeInterval(14 * 86_400),
  settings: settings)
let plan = planner.notificationPlan(alerts, from: now)
```

Reminders may be up to `maximumReminderOffset` long, two hours by default; the planner rejects
a longer one rather than cutting it short. The ``AlertBudget`` is your app's share of the
system's pending requests: 60 by default, leaving a few for anything else your app schedules.
Give each namespace its own share if your app has several.

The plan reports its coverage:

```swift
print(plan.alerts.count, "requests, complete until", plan.coveredUntil)
if let atTime = plan.coverageByKind[.atTime] {
  print("Prayer-time alerts complete until", atTime)
}
```

``NotificationPlan/coveredUntil`` is the end of the interval, from now, in which every enabled
alert is in the plan. Planned at midnight with the default budget and a reminder before and
after each of the five prayers, that's the third day's first reminder; it isn't the last
selected alert's time. Each kind of alert has its own cutoff in
``NotificationPlan/coverageByKind``, so the prayer-time alerts reach further: in that example,
to the ninth day's Fajr.

### Install it

``NotificationScheduler`` installs a plan through the app's notification center and reads it
back:

```swift
let scheduler = NotificationScheduler(
  identifierPrefix: "com.example.prayers.", namespace: "prayers",
  threadIdentifier: "prayers")
let report = try await scheduler.apply(plan) { alert in
  let content = UNMutableNotificationContent()
  content.title = names.name(of: alert.event)
  content.body = alert.kind == .atTime ? "It's time to pray." : "The prayer is near."
  content.sound = alert.sound.notificationSound
  return content
}
for (identity, failure) in report.failures {
  print("\(identity.prayer) on \(identity.scheduleDay): \(failure)")
}
```

Each request's identifier is its alert's ``NotificationIdentity``: the namespace, the prayer's
owning day, the prayer and the kind of alert, with no time in it. When a calculation changes or
the user moves a reminder, adding the new request replaces the old one; nothing is removed
first. The scheduler removes only its own requests that the plan no longer wants, and never
asks for notification permission: ask when the user turns alerts on.

The ``NotificationApplyReport`` says what the read-back confirmed: ``NotificationApplyReport/confirmedCoveredUntil``
ends at the first alert that isn't there as planned, whether its add failed, permission was
denied, or an older request sits under its identifier. It never claims more than the
read-back showed, and neither it nor the plan proves that a notification was seen or heard.

Replan when the app launches, when it becomes active, when the settings or the source change,
and when background refresh gives you the chance. Background refresh is an opportunity, not a
deadline: show the coverage, so your users know when to open the app.

The content closure runs on the scheduler's actor. In a module that defaults to the main actor,
build the content from values the closure captured, and keep any helper it calls
`nonisolated`.

### Missing times shorten coverage

A prayer time the source doesn't know never becomes an alert. It becomes an ``AlertGap``,
moved by each kind's offset: an unknown Isha makes the Isha alert unknown from Maghrib, and its
10-minute reminder unknown ten minutes earlier. The plan's coverage ends there.

```swift
for gap in alerts.gaps {
  let prayers = gap.prayers.map(\.rawValue).sorted().joined(separator: ", ")
  print("\(gap.kind) alerts for \(prayers) on \(gap.day) unknown: \(gap.reason)")
}
```

A gap in a prayer whose alerts are off changes nothing. A timetable that ends, a polar summer's
Isha and a day the source can't calculate all shorten the coverage the same way.

### Apps that keep running

A menu-bar app can follow every alert itself, reminders the plan left out included.
``InProcessAlertEngine`` reports each alert once when it comes due, catches up after sleep (at
prayer time for five minutes, a reminder for two), and never reports a before-reminder once its
prayer has started.

```swift
let engine = InProcessAlertEngine { due in
  Task { _ = try? await scheduler.deliver(due, content: makeContent) }
  let ownSounds = due.filter { $0.sound != .system && $0.sound != .none }
  if let alert = InProcessAlertEngine.preferredAlert(among: ownSounds) {
    play(alert)
  }
}
let now = Date()
engine.update(
  try AlertPlanner().schedule(
    schedule, namespace: "prayers", from: now.addingTimeInterval(-5 * 60),
    to: now.addingTimeInterval(2 * 86_400), settings: settings))
// On wake, after a clock change and when the app becomes active:
engine.resync()
```

``NotificationScheduler/deliver(_:content:)`` posts a due alert at once unless the system will
deliver it or already has, so the notification plan and the engine never alert twice.
``InProcessAlertEngine/preferredAlert(among:)`` picks one sound when several alerts fall due
together. Include the catch-up interval in the engine's range, as above.

### What the package doesn't promise

- **Atomic updates.** A batch can stop part way, an add can fail, and another writer can change
  the center. The next `apply` reconciles again; the report says what's there now.
- **Several writers.** Designate one process and one scheduler per namespace. A widget or
  extension asks that owner to replan.
- **Delivery.** The system decides what is shown and heard: Focus, notification settings and
  sound limits apply.

## See Also

- ``AlertPlanner``
- ``NotificationScheduler``
- ``InProcessAlertEngine``
