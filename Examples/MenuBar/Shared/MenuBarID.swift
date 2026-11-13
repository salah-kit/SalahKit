import Foundation
import SalahWidgets

/// The identifiers the app, the widget extension and the stop harness share.
nonisolated enum MenuBarID {
  /// The App Group the app, the widget extension and the stop harness share.
  ///
  /// The build writes `APP_GROUP_IDENTIFIER` (Config/Shared.xcconfig, or your own in
  /// Config/Local.xcconfig) into each target's entitlements and into the `AppGroupIdentifier`
  /// key of its Info.plist, where this reads it, so the code and the entitlements always name
  /// the same group. A process without the key gets the example's own.
  static let appGroup =
    Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    ?? "group.com.omarkhaled.salah.examples.MenuBar"
  /// The widget's kind, which the app names when it asks WidgetKit for a reload.
  static let widgetKind = "com.omarkhaled.salah.examples.MenuBar.prayers"
  /// The signal the widget's Stop button posts and the running app observes. The name belongs
  /// to this app, so no other process posts it by accident.
  static let stopSignal = DarwinSignal(name: "com.omarkhaled.salah.examples.MenuBar.stop")
  /// The `os.Logger` subsystem of every target.
  static let logSubsystem = "com.omarkhaled.salah.examples.MenuBar"
}
