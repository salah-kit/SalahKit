import Foundation
import Observation
import SalahWidgets
import WatchConnectivity
import os

/// The watch app's state: the stored inputs, the last receipt and the iPhone session.
///
/// Everything it shows comes from the watch's own storage. The session only delivers new
/// inputs; with the iPhone app closed or the iPhone away, the watch shows what it stored last.
@MainActor @Observable
final class WatchModel {
  /// The stored inputs, or `nil` before the first ones arrive.
  private(set) var inputs: WatchInputs?
  /// What the watch received last.
  private(set) var receipt: InputsReceipt?
  /// The iPhone session's state, in a few words.
  private(set) var phone: PhoneLink = .unsupported
  /// Why the last received context was rejected, if it was.
  private(set) var problem: String?

  let options: LaunchOptions
  let strings: AppStrings

  @ObservationIgnored private let receiver = InputsReceiver()
  @ObservationIgnored private var bridge: WatchSessionBridge?
  private static let logger = Logger(subsystem: WatchStorage.subsystem, category: "watch")

  /// The iPhone session's state.
  enum PhoneLink: Equatable, Sendable {
    /// WatchConnectivity isn't available.
    case unsupported
    /// The session isn't active yet.
    case inactive
    /// Active; `reachable` when the iPhone app can be messaged right now.
    case active(reachable: Bool)
  }

  init(options: LaunchOptions) {
    self.options = options
    strings = AppStrings(language: options.language)
    if options.resetInputs {
      receiver.reset(at: Date())
    }
    if let preset = options.preset {
      let now = options.date()
      let outcome = receiver.store(
        InputsMessage(inputs: preset.inputs(today: now), sentAt: Date()), origin: .launchArguments,
        at: Date())
      Self.logger.notice(
        "Stored preset \(preset.rawValue, privacy: .public): \(String(describing: outcome), privacy: .public)"
      )
    }
    reload()
    if WCSession.isSupported() {
      let bridge = WatchSessionBridge(
        receiver: receiver
      ) { [weak self] event in
        Task { @MainActor in self?.handle(event) }
      }
      self.bridge = bridge
      phone = .inactive
      WCSession.default.delegate = bridge
      WCSession.default.activate()
    }
  }

  /// Reads the stored inputs and receipt again.
  func reload() {
    inputs = SharedValue.inputs.load()
    receipt = SharedValue.receipt.load()
  }

  /// Waits, briefly, for WatchConnectivity to deliver what it has pending, when the system
  /// wakes the app in the background for it.
  func finishPendingTransfers() async {
    for _ in 0..<20 where WCSession.default.hasContentPending {
      try? await Task.sleep(for: .milliseconds(500))
    }
  }

  private func handle(_ event: WatchSessionBridge.Event) {
    switch event {
    case .link(let link):
      phone = link
    case .received(let outcome):
      Self.logger.notice("Received inputs: \(String(describing: outcome), privacy: .public)")
      if case .rejected(let reason) = outcome {
        problem = reason
      } else {
        problem = nil
      }
      reload()
    }
  }
}

/// The WatchConnectivity delegate. WatchConnectivity calls it on its own queue; it stores what
/// arrives there, through ``InputsReceiver``, and reports to the model on the main actor.
nonisolated final class WatchSessionBridge: NSObject, WCSessionDelegate, Sendable {
  /// What happened in the session.
  enum Event: Sendable {
    case link(WatchModel.PhoneLink)
    case received(InputsReceiver.Outcome)
  }

  private let receiver: InputsReceiver
  private let report: @Sendable (Event) -> Void

  /// - Parameters:
  ///   - receiver: Stores received inputs.
  ///   - report: Called with each event, on WatchConnectivity's queue.
  init(
    receiver: InputsReceiver, report: @escaping @Sendable (Event) -> Void
  ) {
    self.receiver = receiver
    self.report = report
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: (any Error)?
  ) {
    report(.link(Self.link(of: session)))
    let last = session.receivedApplicationContext
    if !last.isEmpty {
      report(.received(receiver.receiveLastContext(last, at: Date())))
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    report(.received(receiver.receive(context: context, at: Date())))
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    report(.link(Self.link(of: session)))
  }

  private static func link(of session: WCSession) -> WatchModel.PhoneLink {
    session.activationState == .activated
      ? .active(reachable: session.isReachable) : .inactive
  }
}
