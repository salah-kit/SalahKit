import AppKit
import SwiftUI

@main
struct MenuBarApp: App {
  /// `nil` while the app hosts unit tests: they make their own objects, and the host stays
  /// inert so it doesn't write the App Group or plan alerts.
  @State private var model: AppModel?
  private let window = ScheduleWindow()

  // The model is made here, once per launch: its initializer applies the launch arguments,
  // saves the settings and starts observing the stop signal.
  init() {
    let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    let hostsUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    let model = hostsUnitTests ? nil : AppModel(options: options)
    _model = State(initialValue: model)
    if options.showWindow, let model {
      // After launch, once AppKit is ready for windows.
      DispatchQueue.main.async { [window] in window.show(model) }
    }
  }

  var body: some Scene {
    MenuBarExtra {
      if let model {
        ScheduleView(model: model)
      }
    } label: {
      MenuBarLabel(model: model)
    }
    .menuBarExtraStyle(.window)
  }
}

/// The dropdown's view in a window, for UI tests (`-showWindow`): macOS can hide a status item
/// behind the camera housing or when the menu bar is full. (A SwiftUI `Window` scene can't be
/// left out of a launch, so the window is AppKit's.)
@MainActor
final class ScheduleWindow {
  private var window: NSWindow?

  func show(_ model: AppModel) {
    let window = NSWindow(
      contentViewController: NSHostingController(rootView: ScheduleView(model: model)))
    window.title = "MenuBar"
    window.styleMask = [.titled, .closable]
    window.identifier = NSUserInterfaceItemIdentifier("schedule")
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
  }
}

/// The status item's title: the display's static text, refreshed at the `.steps` plan's dates.
struct MenuBarLabel: View {
  let model: AppModel?

  var body: some View {
    if let title = model?.display.content?.title {
      Text(verbatim: title.text)
        .accessibilityLabel(Text(verbatim: title.accessibilityLabel))
    } else {
      Text(verbatim: "MenuBar")
    }
  }
}
