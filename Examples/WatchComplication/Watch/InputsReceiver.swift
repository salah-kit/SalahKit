import Foundation
import SalahWidgets

/// The watch's receive-and-store path: a received application context becomes the stored
/// inputs, and the complication reloads only when they changed.
nonisolated struct InputsReceiver: Sendable {
  /// What happened to a received context.
  enum Outcome: Equatable, Sendable {
    /// The inputs were stored; `changed` says whether they differed, which reloaded the
    /// complication.
    case stored(changed: Bool)
    /// This send was already handled, such as the session's last context read again at
    /// launch.
    case alreadyReceived
    /// The context couldn't be used; the stored inputs stay as they were.
    case rejected(String)
  }

  /// Where the inputs are stored.
  var inputs: SharedValue<WatchInputs> = .inputs
  /// Where the last receipt is stored.
  var receipt: SharedValue<InputsReceipt> = .receipt
  /// The widget kinds to reload when the inputs change.
  var widgetKinds: [String] = [WatchStorage.complicationKind]

  /// Handles a context received from the companion.
  func receive(context: [String: Any], at now: Date) -> Outcome {
    let message: InputsMessage
    do {
      message = try InputsMessage(context: context)
    } catch {
      return .rejected(String(describing: error))
    }
    return store(message, origin: .companion, at: now)
  }

  /// Stores a message's inputs, reloading the complication only when they changed.
  func store(_ message: InputsMessage, origin: InputsReceipt.Origin, at now: Date) -> Outcome {
    if let last = receipt.load(), last.sentAt == message.sentAt, last.origin == origin,
      last.fingerprint == message.inputs.fingerprint
    {
      return .alreadyReceived
    }
    let changed: Bool
    do {
      changed = try inputs.save(message.inputs, reloading: widgetKinds)
      try receipt.save(
        InputsReceipt(
          sentAt: message.sentAt, receivedAt: now, changed: changed,
          fingerprint: message.inputs.fingerprint, origin: origin))
    } catch {
      return .rejected(String(describing: error))
    }
    return .stored(changed: changed)
  }

  /// Removes the stored inputs and receipt, as on a fresh install, and reloads the
  /// complication if there were inputs.
  func reset() {
    _ = try? inputs.save(nil, reloading: widgetKinds)
    _ = try? receipt.save(nil)
  }
}
