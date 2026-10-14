#if canImport(notify)
  import Dispatch
  import notify

  /// A named signal to processes that are already running, such as a widget's button telling
  /// its app to stop playback.
  ///
  /// A Darwin notification carries no data, isn't queued for a process that isn't observing,
  /// and never launches or wakes an app. Use it for actions that only make sense while the
  /// receiver runs, and keep the state they act on somewhere durable, such as a ``SharedValue``.
  ///
  /// The receiver acts on the signal, not on a value stored next to it. A value written by the
  /// widget's process reaches the app's process through the system's preferences daemon, which
  /// can lag behind the signal; an app that checks the stored value when the signal arrives can
  /// read the old one and do nothing. Salah's stop button failed that way until its app acted on
  /// the signal alone.
  ///
  /// ```swift
  /// // In the widget's App Intent, which runs in the extension's process:
  /// DarwinSignal.stopPlayback.post()
  ///
  /// // In the app, on the main actor:
  /// stopObservation = DarwinSignal.stopPlayback.observe { player.stop() }
  /// ```
  ///
  /// The name is shared by every process on the device. Use a name your app owns, such as
  /// `"com.example.prayers.stop"`.
  nonisolated public struct DarwinSignal: Hashable, Sendable {
    /// The signal's name.
    public let name: String

    /// Creates a signal.
    ///
    /// - Parameter name: The name processes post and observe, such as
    ///   `"com.example.prayers.stop"`.
    public init(name: String) {
      self.name = name
    }

    /// Posts the signal to every process observing its name.
    ///
    /// - Returns: Whether the system accepted the signal. Acceptance doesn't mean any process
    ///   was observing.
    @discardableResult
    public func post() -> Bool {
      notify_post(name) == UInt32(NOTIFY_STATUS_OK)
    }

    /// Calls `handler` on the main actor each time any process posts the signal, until the
    /// returned observation is cancelled or released.
    ///
    /// Signals posted while the process doesn't observe are lost, and several posts close
    /// together can arrive as one call.
    ///
    /// - Parameter handler: The work to do for the signal.
    /// - Returns: The observation. Keep it for as long as you want the handler called.
    @MainActor
    public func observe(_ handler: @escaping @MainActor () -> Void) -> Observation {
      let delivery = Delivery(handler: handler)
      var token: Int32 = 0
      // notify(3) calls back on a private queue, and the handler hops to the main actor from
      // there: the main queue isn't always the main thread (a tool that calls `dispatchMain()`
      // services it from another one), so nothing assumes it. The hop holds the delivery weakly,
      // so a signal that arrives while the main actor is busy doesn't call the handler after the
      // observation ends.
      let status = notify_register_dispatch(name, &token, Self.queue) {
        @Sendable [weak delivery] _ in
        Task { @MainActor [weak delivery] in delivery?.handler() }
      }
      guard status == UInt32(NOTIFY_STATUS_OK) else {
        return Observation(token: nil, delivery: nil)
      }
      return Observation(token: token, delivery: delivery)
    }

    /// The queue notify(3) calls back on.
    private static let queue = DispatchQueue(label: "io.github.salah-kit.DarwinSignal")

    /// The handler of one observation, which only the observation keeps alive.
    @MainActor
    final class Delivery {
      let handler: @MainActor () -> Void

      init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
      }
    }

    /// An observation of a ``DarwinSignal``. Releasing it ends the observation.
    @MainActor
    public final class Observation {
      private var token: Int32?
      private var delivery: Delivery?

      init(token: Int32?, delivery: Delivery?) {
        self.token = token
        self.delivery = delivery
      }

      /// Whether the observation was registered and hasn't been cancelled.
      public var isActive: Bool { token != nil }

      /// Stops calling the handler, including for a signal that arrived but hasn't been
      /// handled yet. Cancelling again does nothing.
      public func cancel() {
        if let token {
          notify_cancel(token)
        }
        token = nil
        delivery = nil
      }

      deinit {
        if let token {
          notify_cancel(token)
        }
      }
    }
  }
#endif
