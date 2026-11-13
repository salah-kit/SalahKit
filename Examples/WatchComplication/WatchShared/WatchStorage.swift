import Foundation
import SalahWidgets

/// The watch's own storage: the App Group that the watch app and its complication share.
///
/// The iPhone has no access to it. The watch app is the only writer of the inputs and the
/// receipt; the complication extension is the only writer of the timeline log.
nonisolated enum WatchStorage {
  /// The App Group of the watch, shared by the watch app and the complication extension only.
  ///
  /// The build writes `APP_GROUP_IDENTIFIER` (Config/Shared.xcconfig, or your own in
  /// Config/Local.xcconfig) into each target's entitlements and into the `AppGroupIdentifier`
  /// key of its Info.plist, where this reads it, so the code and the entitlements always name
  /// the same group. A process without the key gets the example's own.
  static let appGroup =
    Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    ?? "group.io.github.salah-kit.WatchComplication.shared"
  /// The complication's widget kind, reloaded when the stored inputs change.
  static let complicationKind = "PrayerComplication"
  /// The logging subsystem of every process in the example.
  static let subsystem = "io.github.salah-kit.WatchComplication"
}

nonisolated extension SharedValue where Value == WatchInputs {
  /// The inputs the watch received last, under a versioned key.
  static var inputs: Self {
    SharedValue(appGroup: WatchStorage.appGroup, key: "inputs.v1")
  }
}

nonisolated extension SharedValue where Value == InputsReceipt {
  /// What the watch app received last, and whether it changed the inputs.
  static var receipt: Self {
    SharedValue(appGroup: WatchStorage.appGroup, key: "receipt.v1")
  }
}

nonisolated extension SharedValue where Value == [TimelineRecord] {
  /// The complication extension's record of its recent timelines.
  static var timelineLog: Self {
    SharedValue(appGroup: WatchStorage.appGroup, key: "timelineLog.v1")
  }
}

/// What the watch app received last.
nonisolated struct InputsReceipt: Codable, Equatable, Sendable {
  /// How the inputs arrived.
  enum Origin: String, Codable, Sendable {
    /// From the companion, over WatchConnectivity.
    case companion
    /// From the `-preset` launch argument, for tests and demos.
    case launchArguments
    /// Removed by the `-resetInputs` launch argument; there are no inputs.
    case reset
  }

  /// When the companion sent the inputs, or when the watch stored or removed them itself.
  var sentAt: Date
  /// When the watch app stored them.
  var receivedAt: Date
  /// Whether they differed from the stored inputs, which reloads the complication.
  var changed: Bool
  /// The inputs' fingerprint.
  var fingerprint: String
  /// How they arrived.
  var origin: Origin
}
