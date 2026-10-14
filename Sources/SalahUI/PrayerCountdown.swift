#if canImport(SwiftUI)
  import SalahCore
  import SwiftUI

  /// The time left until a prayer starts.
  ///
  /// ```swift
  /// if let next = state.nextPrayer {
  ///   PrayerCountdown(to: next, at: state.date)
  /// }
  /// ```
  ///
  /// The ``Mode/live`` countdown is a `Text(timerInterval:)` that SwiftUI updates by itself, in a
  /// widget too, so a timeline needs an entry only where the state changes
  /// (`RefreshStrategy.stateChanges`). The ``Mode/staticText`` countdown is the time left at
  /// `date`, rounded down, in SalahCore's compact form (`45s`, `12m`, `2:15`): it changes only
  /// when the view is drawn again, so pair it with a timeline of
  /// `RefreshStrategy.steps(fine:coarse:window:)` entries.
  ///
  /// Both stop at zero once the prayer has started. Pass only an event the schedule knows will
  /// come next, such as `PrayerState.nextPrayer`: when the next prayer is unknown, show no
  /// countdown at all. Digits follow the environment's locale; set it to a locale from
  /// `PrayerLocale.resolved(_:)` for native digits.
  public struct PrayerCountdown: View {
    /// How a countdown updates.
    nonisolated public enum Mode: Hashable, Sendable {
      /// A timer that counts down by itself, every second.
      case live
      /// The time left at the given date, drawn once.
      case staticText
    }

    private let content: CountdownContent
    private let mode: Mode
    @Environment(\.locale) private var locale
    @Environment(\.prayerTimerFrozen) private var frozen

    /// Creates a countdown.
    ///
    /// - Parameters:
    ///   - event: The prayer to count down to.
    ///   - date: The moment the countdown starts from, such as the state's or the timeline
    ///     entry's date.
    ///   - mode: Whether the countdown updates by itself or shows the time left at `date`.
    public init(to event: PrayerEvent, at date: Date, mode: Mode = .live) {
      content = CountdownContent(from: date, to: event.time)
      self.mode = mode
    }

    /// The remaining time rendered in the environment's locale and requested countdown mode.
    public var body: some View {
      content.text(mode: mode, locale: locale, frozen: frozen)
    }
  }

  extension CountdownContent {
    /// Elapsed time, using the same compact and spoken formatting as a countdown.
    @MainActor
    func elapsedText(mode: PrayerCountdown.Mode, locale: Locale, frozen: Bool = false) -> Text {
      switch mode {
      case .live:
        if frozen {
          return Text(
            timerInterval: start...end, pauseTime: end, countsDown: false, showsHours: true)
        }
        return Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: true)
      case .staticText:
        return Text(verbatim: compactText(locale: locale))
          .accessibilityLabel(Text(verbatim: spokenText(locale: locale)))
      }
    }

    /// The countdown as text: a timer, or the compact time left with a spoken label.
    ///
    /// A frozen timer counts the same length of time over an interval far in the future, so it
    /// shows the time left at `start` whatever the clock says; only tests freeze it.
    @MainActor
    func text(mode: PrayerCountdown.Mode, locale: Locale, frozen: Bool = false) -> Text {
      switch mode {
      case .live:
        let interval =
          frozen ? Date.distantFuture...Date.distantFuture.addingTimeInterval(seconds) : start...end
        return Text(timerInterval: interval, countsDown: true, showsHours: true)
      case .staticText:
        return Text(verbatim: compactText(locale: locale))
          .accessibilityLabel(Text(verbatim: spokenText(locale: locale)))
      }
    }
  }

  extension EnvironmentValues {
    /// Whether live countdowns show the time left at their start instead of running, so a
    /// rendered image is the same whatever the clock says. Only tests set it.
    var prayerTimerFrozen: Bool {
      get { self[PrayerTimerFrozenKey.self] }
      set { self[PrayerTimerFrozenKey.self] = newValue }
    }
  }

  private struct PrayerTimerFrozenKey: EnvironmentKey {
    static var defaultValue: Bool { false }
  }
#endif
