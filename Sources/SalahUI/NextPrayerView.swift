#if canImport(SwiftUI)
  import SalahCore
  import SwiftUI

  /// The next prayer of a state: its name, time and countdown, and the prayer that just
  /// started.
  ///
  /// ```swift
  /// if case .available(let state, _) = schedule.state(at: now, through: bound) {
  ///   NextPrayerView(state: state, names: names, timeZone: schedule.location.timeZone)
  /// }
  /// ```
  ///
  /// The view shows what the state knows and nothing more. When the state's next prayer is
  /// unknown, as after the last published day of a timetable, it has no name, time or
  /// countdown to show; the style shows a placeholder. An unavailable schedule state has no
  /// `PrayerState` at all: show your own wording for it instead of this view.
  ///
  /// The time is in `timeZone`, the schedule's zone, rather than the device's, and is written
  /// in the environment's locale. Set the look with ``SwiftUICore/View/nextPrayerStyle(_:)``;
  /// without one, the view uses ``PlainNextPrayerStyle``.
  public struct NextPrayerView: View {
    private let state: PrayerState
    private let names: PrayerNames
    private let timeZone: TimeZone
    private let mode: PrayerCountdown.Mode
    @Environment(\.locale) private var locale
    @Environment(\.prayerTimerFrozen) private var frozen
    @Environment(\.nextPrayerStyle) private var style

    /// Creates a view of the state's next prayer.
    ///
    /// - Parameters:
    ///   - state: The state to show.
    ///   - names: The names to show, in their locale.
    ///   - timeZone: The schedule's time zone, the location's.
    ///   - countdown: Whether the countdown updates by itself or shows the time left at the
    ///     state's date.
    public init(
      state: PrayerState, names: PrayerNames, timeZone: TimeZone,
      countdown: PrayerCountdown.Mode = .live
    ) {
      self.state = state
      self.names = names
      self.timeZone = timeZone
      mode = countdown
    }

    public var body: some View {
      let content = NextPrayerContent(
        state: state, names: names, timeZone: timeZone, locale: locale)
      let configuration = NextPrayerConfiguration(
        state: state, name: content.name.map { Text(verbatim: $0) },
        // VoiceOver reads an abbreviation as the full name, so a compact style that shows "A"
        // still says "Asr".
        abbreviation: content.abbreviation.map {
          Text(verbatim: $0).accessibilityLabel(Text(verbatim: content.name ?? $0))
        },
        time: content.time.map { Text(verbatim: $0) },
        countdown: content.countdown?.text(mode: mode, locale: locale, frozen: frozen),
        justStarted: content.justStarted.map { Text(verbatim: $0) })
      if let style {
        style.makeBody(configuration)
      } else {
        PlainNextPrayerStyle().makeBody(configuration: configuration)
      }
    }
  }
#endif
