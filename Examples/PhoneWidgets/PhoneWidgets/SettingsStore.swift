import Foundation
import Observation
import SalahTimes
import SalahWidgets

/// What the last save did to the stored settings.
nonisolated enum SaveOutcome: Hashable, Sendable {
  /// The stored value changed, so the app asked WidgetKit to reload the widget.
  case reloadRequested
  /// The stored value was already the same: nothing was written and no reload was requested.
  case unchanged
  /// The App Group couldn't be opened or the value couldn't be encoded.
  case failed(String)
}

/// The settings the app shows, saved to the App Group on every change.
///
/// Every save goes through `SharedValue.save(_:reloading:)` with the widget's kind, which asks
/// for a reload only when the stored value changed; the store keeps that answer so the app can
/// show it.
@MainActor
@Observable
final class SettingsStore {
  /// The settings, or `nil` before the app is set up.
  private(set) var settings: WidgetSettings?
  /// What the last save did, or `nil` before the first save of this run.
  private(set) var lastSave: SaveOutcome?
  /// How many saves this run made, so a repeated outcome still reads as a new save.
  private(set) var saveCount = 0
  @ObservationIgnored private let shared: SharedValue<WidgetSettings>

  /// Loads the stored settings and applies the launch arguments.
  ///
  /// `-cleanStart` removes the stored settings first. The place, method and language arguments
  /// change the settings as if they were made in the app, starting from the stored settings or
  /// the defaults, and save them.
  init(shared: SharedValue<WidgetSettings> = .widgetSettings, options: LaunchOptions) {
    self.shared = shared
    if options.cleanStart {
      _ = try? shared.save(nil, reloading: [PhoneWidgetsID.widgetKind])
    }
    settings = shared.load()
    if options.changesSettings {
      update { options.apply(to: &$0) }
    }
  }

  /// Changes the settings, starting from the defaults before the app is set up, and saves them.
  func update(_ change: (inout WidgetSettings) -> Void) {
    var next = settings ?? .defaults
    change(&next)
    save(next)
  }

  /// Saves the current settings again, unchanged: the save reloads nothing.
  func saveAgain() {
    guard let settings else { return }
    save(settings)
  }

  private func save(_ value: WidgetSettings) {
    saveCount += 1
    do {
      let changed = try shared.save(value, reloading: [PhoneWidgetsID.widgetKind])
      lastSave = changed ? .reloadRequested : .unchanged
      settings = value
    } catch {
      lastSave = .failed(String(describing: error))
    }
  }
}
