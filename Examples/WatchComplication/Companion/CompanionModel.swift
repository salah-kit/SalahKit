import Foundation
import Observation
import WatchConnectivity
import os

/// The companion's state: the session with the watch, the chosen preset and what was sent.
///
/// The companion sends inputs with `updateApplicationContext(_:)`: the watch needs only the
/// latest inputs, and a newer context replaces one the watch hasn't received yet instead of
/// queueing behind it, as `transferUserInfo(_:)` would. The system delivers it when the watch
/// app next runs, whether or not the companion is still running.
@MainActor @Observable
final class CompanionModel {
  /// The session's state, refreshed on every session event.
  private(set) var link = WatchLink()
  /// The preset to send.
  var preset: InputsPreset
  /// The last send's result.
  private(set) var lastSend: SendResult?

  let options: LaunchOptions
  let strings: AppStrings

  @ObservationIgnored private var bridge: CompanionSessionBridge?
  @ObservationIgnored private var sendsWhenActive: Bool
  private static let logger = Logger(
    subsystem: "io.github.salah-kit.WatchComplication", category: "companion")

  /// The session's state, as the companion shows it.
  struct WatchLink: Equatable, Sendable {
    var supported = false
    var activation: WCSessionActivationState = .notActivated
    var isPaired = false
    var isWatchAppInstalled = false
    var isReachable = false
    /// The inputs of the session's current application context: what the watch gets next or
    /// got last, even after the companion relaunches.
    var pendingFingerprint: String?
    var pendingSentAt: Date?
  }

  /// What happened to a send.
  struct SendResult: Equatable, Sendable {
    var preset: InputsPreset
    var fingerprint: String
    var sentAt: Date
    /// `nil` when WatchConnectivity accepted the context; otherwise why it didn't.
    var error: String?
  }

  init(options: LaunchOptions) {
    self.options = options
    strings = AppStrings(language: options.language)
    preset = options.preset ?? .makkah
    sendsWhenActive = options.send
    guard WCSession.isSupported() else { return }
    link.supported = true
    let bridge = CompanionSessionBridge { [weak self] link in
      Task { @MainActor in self?.update(link) }
    }
    self.bridge = bridge
    WCSession.default.delegate = bridge
    WCSession.default.activate()
  }

  /// Sends the chosen preset's inputs as the session's application context.
  func send() {
    let now = options.date()
    let message = InputsMessage(inputs: preset.inputs(today: now), sentAt: Date())
    var result = SendResult(
      preset: preset, fingerprint: message.inputs.fingerprint, sentAt: message.sentAt)
    do {
      guard link.supported else { throw CompanionError.unsupported }
      try WCSession.default.updateApplicationContext(message.context())
      Self.logger.notice(
        "Sent \(self.preset.rawValue, privacy: .public) inputs \(result.fingerprint, privacy: .public)"
      )
    } catch {
      result.error = (error as NSError).localizedDescription
      Self.logger.error("Send failed: \(String(describing: error), privacy: .public)")
    }
    lastSend = result
    if link.supported {
      update(CompanionSessionBridge.link(of: WCSession.default))
    }
  }

  private func update(_ link: WatchLink) {
    self.link = link
    if sendsWhenActive, link.activation == .activated {
      sendsWhenActive = false
      send()
    }
  }

  private enum CompanionError: LocalizedError {
    case unsupported
    var errorDescription: String? { "WatchConnectivity isn't supported on this device." }
  }
}

/// The WatchConnectivity delegate. It reads the session's state on WatchConnectivity's queue
/// and reports it to the model on the main actor.
nonisolated final class CompanionSessionBridge: NSObject, WCSessionDelegate, Sendable {
  private let report: @Sendable (CompanionModel.WatchLink) -> Void

  init(report: @escaping @Sendable (CompanionModel.WatchLink) -> Void) {
    self.report = report
  }

  /// The session's state now.
  static func link(of session: WCSession) -> CompanionModel.WatchLink {
    var link = CompanionModel.WatchLink()
    link.supported = true
    link.activation = session.activationState
    if session.activationState == .activated {
      link.isPaired = session.isPaired
      link.isWatchAppInstalled = session.isWatchAppInstalled
      link.isReachable = session.isReachable
      if let message = try? InputsMessage(context: session.applicationContext) {
        link.pendingFingerprint = message.inputs.fingerprint
        link.pendingSentAt = message.sentAt
      }
    }
    return link
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: (any Error)?
  ) {
    report(Self.link(of: session))
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
    report(Self.link(of: session))
  }

  func sessionDidDeactivate(_ session: WCSession) {
    // The user switched to another watch: activate again for it.
    session.activate()
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    report(Self.link(of: session))
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    report(Self.link(of: session))
  }
}
