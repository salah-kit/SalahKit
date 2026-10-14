# ``SalahAlerts``

Alerts for prayer times: the complete schedule an app can follow, the requests an operating
system can keep, and an honest account of how far they reach.

## Overview

An app chooses, per prayer, whether it wants an alert at the prayer's time, a reminder before
it and a reminder after it. ``AlertPlanner`` turns those settings and a `PrayerSchedule` into
an ``AlertSchedule``: every enabled alert in a range, and the intervals where a prayer time the
source doesn't know could hide one. From that schedule it plans a ``NotificationPlan`` that fits
a request budget, and says until when the plan is complete.

``NotificationScheduler`` installs a plan as pending notification requests under stable
identifiers, reads them back, and reports only what it confirmed. ``InProcessAlertEngine``
follows the whole schedule inside an app that keeps running, catches up after sleep, and
reports each alert once.

An always-running app chooses excluded occurrence keys from the engine's
``InProcessAlertEngine/handledOccurrences`` and passes them to
``AlertPlanner/notificationPlan(_:from:budget:excluding:)``. Clock changes capture prior keys
before resyncing; ordinary replans preserve future requests during early delivery. The record
lasts a day in memory; it records engine reports, not system delivery.

SalahAlerts never invents an alert. A missing prayer time gets none and shortens the coverage
the planner reports; a request the system didn't keep shortens the coverage the scheduler
reports. The package ships no sounds and never asks for notification permission: wording,
sounds, audio playback and authorization stay with the app.

The planner, the identities and the engine build on every platform SalahKit supports,
Linux included. The scheduler needs UserNotifications and isn't available on tvOS.
[RFC 0003](https://github.com/salah-kit/SalahKit/blob/main/docs/rfcs/0003-alerts.md)
specifies all of it, and the vectors in `Vectors/alerts` and `Vectors/reconciliation` encode it.

## Topics

### Essentials

- <doc:AlertsWithinTheNotificationLimit>
- ``AlertPlanner``
- ``AlertSettings``

### Settings and identity

- ``AlertKind``
- ``AlertSound``
- ``AlertSubject``
- ``NotificationIdentity``
- ``AlertOccurrenceID``
- ``PlannedAlert``

### Planning

- ``AlertSchedule``
- ``AlertGap``
- ``AlertBudget``
- ``NotificationPlan``
- ``AlertPlanningError``

### Notification requests

- ``NotificationScheduler``
- ``NotificationApplyReport``
- ``NotificationApplyFailure``
- ``NotificationDeliveryReport``
- ``NotificationSchedulerError``
- ``AlertNotificationCenter``
- ``DeliveredNotificationRecord``

### Alerts in a running app

- ``InProcessAlertEngine``
- ``CatchUpPolicy``
- ``AlertClock``
- ``SystemAlertClock``
