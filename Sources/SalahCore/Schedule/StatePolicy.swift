import Foundation

/// The app's choices for the time-dependent parts of a state: when a prayer counts as
/// approaching, and how long it counts as just started.
///
/// Durations below zero count as zero. The policy encodes durations as seconds:
/// `{"approaching": 900, "justStarted": {"untilIqama": {"fallback": 900}}}`.
nonisolated public struct StatePolicy: Codable, Hashable, Sendable {
  /// How long a prayer counts as just started.
  ///
  /// Encodes as `{"fixed": seconds}` or `{"untilIqama": {"fallback": seconds}}`.
  public enum JustStarted: Codable, Hashable, Sendable {
    /// A fixed duration after the prayer's time.
    case fixed(Duration)
    /// Until the prayer's iqama, or for the fallback duration when it has none. An iqama at
    /// the prayer's own time gives no just-started window.
    case untilIqama(fallback: Duration)

    private enum CodingKeys: String, CodingKey {
      case fixed, untilIqama
    }

    private enum FallbackKeys: String, CodingKey {
      case fallback
    }

    /// Decodes `{"fixed": seconds}` or `{"untilIqama": {"fallback": seconds}}`.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let seconds = try container.decodeIfPresent(Double.self, forKey: .fixed) {
        self = .fixed(.seconds(seconds))
      } else if container.contains(.untilIqama) {
        let nested = try container.nestedContainer(keyedBy: FallbackKeys.self, forKey: .untilIqama)
        self = .untilIqama(fallback: .seconds(try nested.decode(Double.self, forKey: .fallback)))
      } else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription:
              "Expected {\"fixed\": seconds} or {\"untilIqama\": {\"fallback\": seconds}}."
          ))
      }
    }

    /// Encodes `{"fixed": seconds}` or `{"untilIqama": {"fallback": seconds}}`.
    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .fixed(let duration):
        try container.encode(duration.seconds, forKey: .fixed)
      case .untilIqama(let fallback):
        var nested = container.nestedContainer(keyedBy: FallbackKeys.self, forKey: .untilIqama)
        try nested.encode(fallback.seconds, forKey: .fallback)
      }
    }
  }

  /// How long before a prayer it counts as approaching. The default is 15 minutes.
  public var approaching: Duration
  /// How long a prayer counts as just started. The default is until its iqama, or 15 minutes
  /// when it has none.
  public var justStarted: JustStarted

  /// Creates a policy.
  public init(
    approaching: Duration = .seconds(15 * 60),
    justStarted: JustStarted = .untilIqama(fallback: .seconds(15 * 60))
  ) {
    self.approaching = approaching
    self.justStarted = justStarted
  }

  private enum CodingKeys: String, CodingKey {
    case approaching, justStarted
  }

  /// Decodes a policy; a missing field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = StatePolicy()
    self.init(
      approaching: try container.decodeIfPresent(Double.self, forKey: .approaching)
        .map { .seconds($0) } ?? defaults.approaching,
      justStarted: try container.decodeIfPresent(JustStarted.self, forKey: .justStarted)
        ?? defaults.justStarted)
  }

  /// Encodes the policy with durations in seconds.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(approaching.seconds, forKey: .approaching)
    try container.encode(justStarted, forKey: .justStarted)
  }
}

extension Duration {
  /// The duration in seconds, as a `Double`.
  nonisolated var seconds: Double {
    let parts = components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }

  /// The duration in seconds as a `TimeInterval`, never below zero.
  nonisolated var nonNegativeSeconds: TimeInterval { Swift.max(0, seconds) }
}
