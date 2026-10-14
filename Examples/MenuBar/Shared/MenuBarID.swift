import Foundation
import SalahWidgets

/// The identifiers the app, the widget extension and the stop harness share.
nonisolated enum MenuBarID {
  /// The App Group every target declares in its entitlements.
  static let appGroup = "group.io.github.salah-kit.MenuBar"
  /// The widget's kind, which the app names when it asks WidgetKit for a reload.
  static let widgetKind = "io.github.salah-kit.MenuBar.prayers"
  /// The signal the widget's Stop button posts and the running app observes. The name belongs
  /// to this app, so no other process posts it by accident.
  static let stopSignal = DarwinSignal(name: "io.github.salah-kit.MenuBar.stop")
  /// The `os.Logger` subsystem of every target.
  static let logSubsystem = "io.github.salah-kit.MenuBar"
}
