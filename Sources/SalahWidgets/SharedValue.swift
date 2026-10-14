import Foundation

#if canImport(WidgetKit)
  import WidgetKit
#endif

/// A `Codable` value that an app and its extensions share through an App Group.
///
/// The app saves its inputs, such as calculation settings or published timetable data, and a
/// widget extension loads them to build its own schedule. Declare the value once, in a file that
/// both targets compile:
///
/// ```swift
/// extension SharedValue where Value == PhoneSettings {
///   // Computed: a generic type can't have a stored static property.
///   static var settings: Self {
///     SharedValue(appGroup: "group.com.example.prayers", key: "settings.v1")
///   }
/// }
///
/// // In the app, whenever the settings change:
/// try SharedValue.settings.save(settings, reloading: ["prayers"])
///
/// // In the widget extension's timeline provider:
/// guard let settings = SharedValue.settings.load() else { /* ask the user to set up */ }
/// ```
///
/// Saving gates widget reloads: ``save(_:reloading:)`` asks WidgetKit to reload the given kinds
/// only when the stored value changed. Saving the same settings again, for example on every
/// launch, costs no reload from the widget's daily budget.
///
/// The value is stored as JSON data in the App Group's `UserDefaults`, under ``key``. Put a
/// version in the key (`"settings.v1"`) and change it when the value's shape changes: a stored
/// value that no longer decodes reads as `nil`. The defaults are read on every call, so a value
/// written by another process is seen once the system has synchronized it, which the platform
/// does on its own schedule.
///
/// `SharedValue` doesn't lock. Give each key one writer, usually the app.
nonisolated public struct SharedValue<Value: Codable & Equatable & Sendable>: Sendable {
  /// The App Group identifier, used as the `UserDefaults` suite name, such as
  /// `"group.com.example.prayers"`.
  public let appGroup: String

  /// The key the value is stored under, such as `"settings.v1"`.
  public let key: String

  private let reloadTimelines: @Sendable ([String]) -> Void

  /// Creates a shared value that reloads widget timelines through WidgetKit.
  ///
  /// - Parameters:
  ///   - appGroup: The App Group identifier. Every target that reads or writes the value needs
  ///     the App Group capability with this identifier.
  ///   - key: The key the value is stored under.
  public init(appGroup: String, key: String) {
    self.init(appGroup: appGroup, key: key, reloadTimelines: Self.reloadWidgetTimelines)
  }

  /// Creates a shared value that reports the widget kinds to reload to your own function instead
  /// of WidgetKit.
  ///
  /// Use it to test what your app saves and when it asks for reloads, or to route reloads
  /// yourself.
  ///
  /// - Parameters:
  ///   - appGroup: The App Group identifier, used as the `UserDefaults` suite name.
  ///   - key: The key the value is stored under.
  ///   - reloadTimelines: Called with the widget kinds to reload, after a save that changed the
  ///     stored value. Never called with an empty list.
  public init(
    appGroup: String, key: String,
    reloadTimelines: @escaping @Sendable (_ widgetKinds: [String]) -> Void
  ) {
    self.appGroup = appGroup
    self.key = key
    self.reloadTimelines = reloadTimelines
  }

  /// The stored value, or `nil` when there is none or it doesn't decode as `Value`.
  public func load() -> Value? {
    guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(Value.self, from: data)
  }

  /// Saves a value, or removes the stored one when `value` is `nil`, and reloads the given
  /// widget kinds only if the stored value changed.
  ///
  /// The stored value changes when no value was stored, when the stored one differs from
  /// `value` by `==`, or when the stored data no longer decodes. An unchanged value isn't
  /// written again and reloads nothing.
  ///
  /// - Parameters:
  ///   - value: The value to store, or `nil` to remove it.
  ///   - widgetKinds: The widget kinds whose timelines depend on the value, such as
  ///     `["prayers"]`. Leave it empty when no widget reads the value.
  /// - Returns: Whether the stored value changed. The reload is requested exactly when this is
  ///   `true` and `widgetKinds` isn't empty.
  /// - Throws: ``SharedValueError`` when the App Group's defaults can't be opened or the value
  ///   can't be encoded. Nothing is written and nothing is reloaded.
  @discardableResult
  public func save(
    _ value: Value?, reloading widgetKinds: [String] = []
  ) throws(SharedValueError) -> Bool {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      throw .appGroupUnavailable(appGroup)
    }
    let stored = defaults.data(forKey: key)
    if let value {
      let data: Data
      do {
        data = try JSONEncoder().encode(value)
      } catch {
        throw .encodingFailed(String(describing: error))
      }
      if let stored, (try? JSONDecoder().decode(Value.self, from: stored)) == value {
        return false
      }
      defaults.set(data, forKey: key)
    } else {
      guard stored != nil else { return false }
      defaults.removeObject(forKey: key)
    }
    if !widgetKinds.isEmpty {
      reloadTimelines(widgetKinds)
    }
    return true
  }

  /// Asks WidgetKit to reload each kind, where WidgetKit exists.
  private static func reloadWidgetTimelines(_ kinds: [String]) {
    #if canImport(WidgetKit)
      if #available(visionOS 26.0, *) {
        for kind in kinds {
          WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
      }
    #endif
  }
}

/// Why a ``SharedValue`` couldn't save.
nonisolated public enum SharedValueError: Error, Hashable, Sendable {
  /// `UserDefaults` has no suite with this name for the process, such as an empty name.
  case appGroupUnavailable(String)
  /// The value couldn't be encoded as JSON, such as a `Double` that isn't finite. The
  /// associated text describes the encoder's error.
  case encodingFailed(String)
}
