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
  /// The list shows the events the day has, sunrise included, in their order. Pass a partial
  /// day's missing kinds and reasons in `missing` to keep their rows in canonical kind order;
  /// those rows carry no event, time, status or countdown. Times are in the day's time
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
    private let missing: [PrayerKind: ScheduleGapReason]

    /// Creates a list of a day's events.
    ///
    /// - Parameters:
    ///   - day: The owning day whose events to show.
    ///   - state: The state the rows' statuses and countdown come from, or `nil` when it isn't
    ///     known.
    ///   - names: The names to show, in their locale.
    ///   - countdown: Whether the next event's countdown updates by itself or shows the time
    ///     left at the state's date.
    ///   - missing: The expected kinds the source could not provide, with their gap reasons.
    ///     Pass the dictionary from `DayCoverage.partial(missing:)`. When nonempty, known and
    ///     missing rows use canonical kind order; a known event wins a conflicting entry.
    ///     The default lists only known events, in their original order.
    public init(
      day: PrayerDay, state: PrayerState?, names: PrayerNames,
      countdown: PrayerCountdown.Mode = .live,
      missing: [PrayerKind: ScheduleGapReason] = [:]
    ) {
      self.day = day
      self.state = state
      self.names = names
      mode = countdown
      self.missing = missing
    }

    /// The styled prayer rows in a vertical stack with no extra spacing.
    public var body: some View {
      VStack(spacing: 0) {
        rows
      }
    }

    /// The styled rows without a containing stack.
    ///
    /// Put these directly inside your own stack when it controls row spacing or available
    /// height. Each style's view is a direct child, so its frame and layout priority take part
    /// in that stack's layout independently of the other rows.
    public var rows: some View {
      PrayerTimesRows(day: day, state: state, names: names, mode: mode, missing: missing)
    }
  }

  /// Resolves the environment after either `PrayerTimesList` or its transparent rows view is
  /// installed in a hierarchy. Reading the list's environment while constructing `.rows`
  /// would lose the caller's locale and style.
  private struct PrayerTimesRows: View {
    let day: PrayerDay
    let state: PrayerState?
    let names: PrayerNames
    let mode: PrayerCountdown.Mode
    let missing: [PrayerKind: ScheduleGapReason]
    @Environment(\.locale) private var locale
    @Environment(\.prayerTimerFrozen) private var frozen
    @Environment(\.prayerRowStyle) private var style

    var body: some View {
      ForEach(
        ListRowContent.rows(day: day, state: state, names: names, locale: locale, missing: missing)
      ) { row in
        let configuration = configuration(for: row)
        if let style {
          style.makeBody(configuration)
        } else {
          PlainPrayerRowStyle().makeBody(configuration: configuration)
        }
      }
    }

    private func configuration(for content: ListRowContent) -> PrayerRowConfiguration {
      switch content {
      case .event(let row):
        PrayerRowConfiguration(
          kind: row.event.kind, event: row.event, gapReason: nil, status: row.status,
          name: Text(verbatim: row.name), time: Text(verbatim: row.time),
          dayOffset: row.dayOffset, dayOffsetText: row.dayOffsetText.map { Text(verbatim: $0) },
          countdown: row.countdown?.text(mode: mode, locale: locale, frozen: frozen))
      case .missing(_, let kind, let reason, let name):
        PrayerRowConfiguration(
          kind: kind, event: nil, gapReason: reason, status: nil,
          name: Text(verbatim: name), time: nil, dayOffset: 0, dayOffsetText: nil, countdown: nil)
      }
    }
  }
#endif
