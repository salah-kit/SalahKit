import SalahCore

/// The known event a next-prayer view emphasizes, and the direction of its timer.
///
/// Selection uses only the schedule's state. An unknown next event never becomes a
/// countdown, and a count-up lasts only while `PrayerState.justStarted` is present.
nonisolated public enum PrayerFocus: Hashable, Sendable {
  /// Count down to a known upcoming event.
  case countdown(PrayerEvent)
  /// Count up from a prayer still inside its just-started window.
  case countUp(PrayerEvent)

  /// Which known event a view emphasizes.
  public enum Selection: Hashable, Sendable {
    /// The next prayer, excluding sunrise.
    case nextPrayer
    /// The next event, including sunrise.
    case nextEvent
    /// The just-started prayer, otherwise the next prayer excluding sunrise.
    case justStartedOrNextPrayer
    /// The just-started prayer, otherwise the next event including sunrise.
    case justStartedOrNextEvent
  }

  /// Selects a focus, or returns `nil` when the state does not know one.
  ///
  /// - Parameters:
  ///   - state: The known schedule state at the displayed moment.
  ///   - selection: Whether sunrise participates and a just-started prayer takes precedence.
  public init?(state: PrayerState, selection: Selection = .nextPrayer) {
    switch selection {
    case .justStartedOrNextPrayer, .justStartedOrNextEvent:
      if let started = state.justStarted {
        self = .countUp(started)
        return
      }
    case .nextPrayer, .nextEvent: break
    }
    let next: PrayerEvent?
    switch selection {
    case .nextPrayer, .justStartedOrNextPrayer: next = state.nextPrayer
    case .nextEvent, .justStartedOrNextEvent: next = state.next
    }
    guard let next else { return nil }
    self = .countdown(next)
  }

  /// The event the focus describes.
  public var event: PrayerEvent {
    switch self {
    case .countdown(let event), .countUp(let event): event
    }
  }

  /// Whether the timer counts up from the event's start.
  public var isCountUp: Bool {
    if case .countUp = self { return true }
    return false
  }
}
