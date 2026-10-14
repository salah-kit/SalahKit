import Foundation

/// The application context the companion sends: the inputs as JSON data, and when they were
/// sent.
///
/// WatchConnectivity carries property-list values only, so the inputs travel as `Data`. The key
/// has a version, like the watch's storage key: a watch app that doesn't know a newer shape
/// ignores it and keeps its last valid inputs.
///
/// The send time makes every send a new context, so the watch can tell a repeated send of the
/// same inputs from one it already handled; the watch's storage still reloads the complication
/// only when the inputs themselves change.
nonisolated struct InputsMessage: Equatable, Sendable {
  /// The context key of the inputs' JSON data.
  static let inputsKey = "inputs.v1"
  /// The context key of the send time.
  static let sentAtKey = "sentAt"

  /// The inputs.
  var inputs: WatchInputs
  /// When the companion sent them.
  var sentAt: Date

  /// The application context for WatchConnectivity.
  func context() throws -> [String: Any] {
    [Self.inputsKey: try inputs.encoded(), Self.sentAtKey: sentAt]
  }

  /// Why a received context can't be used.
  enum DecodingProblem: Error, Equatable, Sendable {
    /// The context has no inputs this version understands.
    case missingInputs
    /// The inputs' data doesn't decode as ``WatchInputs``.
    case undecodable(String)
  }

  /// Reads a received application context.
  ///
  /// - Throws: ``DecodingProblem`` when the context has no inputs of this version, or they
  ///   don't decode.
  init(context: [String: Any]) throws(DecodingProblem) {
    guard let data = context[Self.inputsKey] as? Data else { throw .missingInputs }
    do {
      inputs = try JSONDecoder().decode(WatchInputs.self, from: data)
    } catch {
      throw .undecodable(String(describing: error))
    }
    sentAt = context[Self.sentAtKey] as? Date ?? .distantPast
  }

  /// A message to send.
  init(inputs: WatchInputs, sentAt: Date) {
    self.inputs = inputs
    self.sentAt = sentAt
  }
}
