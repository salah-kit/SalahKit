import Foundation
import Observation
import SalahAlerts
import SalahCore
import SalahUI

/// The menu bar's title: short text, and what VoiceOver reads.
nonisolated struct MenuBarTitle: Hashable, Sendable {
  var text: String
  var accessibilityLabel: String
}

/// What the app shows, from one refresh-plan entry.
nonisolated struct DisplayContent: Hashable, Sendable {
  /// The entry's date: the moment the static text describes.
  var date: Date
  /// The schedule's state from `date` until the next entry.
  var state: ScheduleState
  /// The day the dropdown lists: the civil day of the refresh, in the place's zone.
  var day: PrayerDayAvailability
  /// The menu bar's title.
  var title: MenuBarTitle
}

/// How the display refreshes, and what its title says.
///
/// The title is static text, so it changes only when the app sets it again. The app refreshes
/// it at the dates of a `.steps` refresh plan: every minute within an hour of a prayer, where the
/// title counts down (or up, just after a prayer starts), and every 15 minutes elsewhere, where it
/// names the next prayer and its time. The plan also has every state change, so the next prayer
/// changes on time.
nonisolated enum MenuBarDisplay {
  /// The plan's strategy.
  static let strategy = RefreshStrategy.steps(
    fine: .seconds(60), coarse: .seconds(15 * 60), window: .seconds(countdownWindow))
  /// How close to its prayer the title counts down, in seconds.
  static let countdownWindow = 60 * 60
  /// How far one plan reaches; the app plans again at its end.
  static let horizon: TimeInterval = 6 * 3_600
  /// The most entries a plan may use. A minute grid around three prayers in six hours needs
  /// about 400; the app isn't WidgetKit, so it isn't bound by Core's default of 96.
  static let limit = 1_000

  /// The refresh plan from `now`, or `nil` when it can't be made.
  static func plan(_ schedule: PrayerSchedule, from now: Date) -> RefreshPlan? {
    try? schedule.refreshPlan(
      from: now, through: now.addingTimeInterval(horizon), strategy: strategy, limit: limit)
  }

  /// The title for a state at the moment it describes.
  ///
  /// - A prayer that just started (StatePolicy's default: until its iqama, or 15 minutes): its
  ///   name and the time since, "Asr +5m".
  /// - The next prayer within an hour: its name and the time left, "Asr 27m".
  /// - The next prayer later: its name and time, "Asr 15:21".
  /// - The next prayer unknown, as when a calculation can't produce it: "Next unknown".
  /// - No usable state: "No times".
  static func title(
    for state: ScheduleState, at date: Date, strings: MenuBarStrings, timeZone: TimeZone
  ) -> MenuBarTitle {
    guard case .available(let prayer, _) = state else {
      return MenuBarTitle(
        text: strings("No times"), accessibilityLabel: strings("No prayer times are known now"))
    }
    guard let focus = PrayerFocus(state: prayer, selection: .justStartedOrNextEvent) else {
      return MenuBarTitle(
        text: strings("Next unknown"),
        accessibilityLabel: strings("The next prayer time isn't known"))
    }
    if case .countUp(let started) = focus {
      let name = strings.names.name(of: started)
      let elapsed = date.timeIntervalSince(started.time)
      return MenuBarTitle(
        text: "\(name) \(strings.elapsed(elapsed))",
        accessibilityLabel: strings("\(name) started \(strings.spoken(elapsed)) ago"))
    }
    let next = focus.event
    let name = strings.names.name(of: next)
    let remaining = next.time.timeIntervalSince(date)
    if remaining <= TimeInterval(countdownWindow) {
      return MenuBarTitle(
        text: "\(name) \(strings.remaining(remaining))",
        accessibilityLabel: strings("\(name) in \(strings.spoken(remaining))"))
    }
    let time = strings.time(next.time, in: timeZone)
    return MenuBarTitle(text: "\(name) \(time)", accessibilityLabel: strings("\(name) at \(time)"))
  }
}

/// Keeps the display current: shows the refresh plan's entry for the clock's moment and arms a
/// wake-up for the next entry, or the next midnight in the place's zone when the listed day
/// changes first.
@MainActor
@Observable
final class DisplayModel {
  /// What the display shows; `nil` when no plan could be made.
  private(set) var content: DisplayContent?
  /// How many times the display was refreshed, for tests.
  private(set) var refreshCount = 0

  @ObservationIgnored private let clock: any AlertClock
  @ObservationIgnored private var settings: MenuBarSettings
  @ObservationIgnored private var schedule: PrayerSchedule
  @ObservationIgnored private var plan: RefreshPlan?

  /// Creates the display and shows the current moment.
  ///
  /// - Parameters:
  ///   - settings: The place, calculation and language.
  ///   - clock: The app's clock. The display arms one wake-up on it at a time.
  init(settings: MenuBarSettings, clock: any AlertClock) {
    self.settings = settings
    schedule = settings.schedule
    self.clock = clock
    refresh()
  }

  /// Shows new settings from the current moment.
  func update(settings: MenuBarSettings) {
    self.settings = settings
    schedule = settings.schedule
    refresh(replanning: true)
  }

  /// Shows the entry for the clock's current moment and arms the next refresh.
  ///
  /// - Parameter replanning: Plans again from now. Pass `true` after the Mac wakes or the clock
  ///   changes: a wake-up armed before can be late or early then, and a plan from now shows the
  ///   exact time left.
  func refresh(replanning: Bool = false) {
    let now = clock.now
    if replanning || plan.map({ !($0.horizon.start <= now && now < $0.validUntil) }) ?? true {
      plan = MenuBarDisplay.plan(schedule, from: now)
    }
    guard let plan, let entry = plan.entries.last(where: { $0.date <= now }) else {
      content = nil
      clock.wake(at: nil) {}
      return
    }
    let zone = settings.place.location.timeZone
    let strings = MenuBarStrings(language: settings.language)
    content = DisplayContent(
      date: entry.date, state: entry.state, day: schedule.day(containing: now),
      title: MenuBarDisplay.title(
        for: entry.state, at: entry.date, strings: strings, timeZone: zone)
    )
    refreshCount += 1
    let nextEntry = plan.entries.first(where: { $0.date > now })?.date ?? plan.validUntil
    let midnight = CivilDay(containing: now, in: zone).adding(days: 1).start(in: zone)
    clock.wake(at: min(nextEntry, midnight)) { [weak self] in self?.refresh() }
  }
}
