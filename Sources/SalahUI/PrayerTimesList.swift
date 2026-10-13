#if canImport(SwiftUI)
  import SalahCore
  import SwiftUI

  /// The events of one owning day, one row each, with their status in a state.
  ///
  /// ```swift
  /// if case .available(let day, _) = schedule.day(containing: now),
  ///   case .available(let state, _) = schedule.state(at: now, through: bound)
  /// {
  ///   PrayerTimesList(day: day, state: state, names: PrayerNames(locale: locale))
  /// }
  /// ```
  ///
  /// The list shows the events the day has, sunrise included, in their order; a partial day
  /// shows the times it has and leaves the rest to your wording. Times are in the day's time
  /// zone, whatever the device's zone, and written in the environment's locale. The row of the
  /// state's next event carries a countdown. Pass `nil` for the state when the schedule can't
  /// establish one, such as while it's unavailable: the rows then show no status and no
  /// countdown.
  ///
  /// The list is a plain vertical stack, so it works in widgets. Set the rows' look with
  /// ``SwiftUICore/View/prayerRowStyle(_:)``; without one, rows use ``PlainPrayerRowStyle``.
  public struct PrayerTimesList: View {
    private let day: PrayerDay
    private let state: PrayerState?
    private let names: PrayerNames
    private let mode: PrayerCountdown.Mode
    @Environment(\.locale) private var locale
    @Environment(\.prayerTimerFrozen) private var frozen
    @Environment(\.prayerRowStyle) private var style

    /// Creates a list of a day's events.
    ///
    /// - Parameters:
    ///   - day: The owning day whose events to show.
    ///   - state: The state the rows' statuses and countdown come from, or `nil` when it isn't
    ///     known.
    ///   - names: The names to show, in their locale.
    ///   - countdown: Whether the next event's countdown updates by itself or shows the time
    ///     left at the state's date.
    public init(
      day: PrayerDay, state: PrayerState?, names: PrayerNames,
      countdown: PrayerCountdown.Mode = .live
    ) {
      self.day = day
      self.state = state
      self.names = names
      mode = countdown
    }

    public var body: some View {
      VStack(spacing: 0) {
        ForEach(
          RowContent.rows(day: day, state: state, names: names, locale: locale), id: \.event.id
        ) {
          row in
          let configuration = PrayerRowConfiguration(
            event: row.event, status: row.status, name: Text(verbatim: row.name),
            time: Text(verbatim: row.time), dayOffset: row.dayOffset,
            dayOffsetText: row.dayOffsetText.map { Text(verbatim: $0) },
            countdown: row.countdown?.text(mode: mode, locale: locale, frozen: frozen))
          if let style {
            style.makeBody(configuration)
          } else {
            PlainPrayerRowStyle().makeBody(configuration: configuration)
          }
        }
      }
    }
  }
#endif
