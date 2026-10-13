import SalahTimes

/// The settings of a calculated prayer source: SalahTimes' calculation parameters, whole.
///
/// Start from a published method and change what your users change:
///
/// ```swift
/// var settings = CalculationSettings(method: .muslimWorldLeague, madhab: .hanafi)
/// settings.parameters.fajr = .angle(18.5)
/// settings.parameters.rounding = .up
/// ```
///
/// or bring parameters you already have with ``init(parameters:)``. ``CalculationSource``
/// passes ``parameters`` to SalahTimes exactly as they are: nothing is rebuilt from a subset or
/// reset to a method's value, so every control SalahTimes has stays in your users' hands. That
/// includes the opt-in Ramadan rule, `CalculationParameters.ramadanIsha`, which
/// changes only an interval-based Isha on days in Ramadan.
///
/// The value is `Codable`, so an app can keep it in its settings or an App Group and give it to
/// a widget extension. Its JSON is `{"parameters": …}`, with the parameters in SalahTimes' own
/// JSON form. It's `Hashable` because SalahTimes' parameters are.
nonisolated public struct CalculationSettings: Codable, Hashable, Sendable {
  /// How SalahTimes computes the times, passed to it unchanged.
  public var parameters: CalculationParameters

  /// Creates settings from SalahTimes parameters, kept exactly as given.
  ///
  /// - Parameter parameters: The calculation parameters.
  public init(parameters: CalculationParameters) {
    self.parameters = parameters
  }

  /// Creates settings from a published method's parameters, with a madhab and, if you opt in,
  /// the Ramadan rule for an interval-based Isha.
  ///
  /// Every other parameter is the method's. Change any of them afterwards on ``parameters``.
  ///
  /// - Parameters:
  ///   - method: The published method to start from.
  ///   - madhab: The school that sets Asr's shadow length.
  ///   - ramadanIsha: The opt-in Ramadan rule; off unless you choose it.
  public init(
    method: CalculationMethod, madhab: Madhab = .shafi, ramadanIsha: RamadanIshaRule = .off
  ) {
    var parameters = method.parameters
    parameters.madhab = madhab
    parameters.ramadanIsha = ramadanIsha
    self.init(parameters: parameters)
  }
}
