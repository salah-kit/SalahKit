import SwiftUI

@main
struct PhoneWidgetsApp: App {
  private let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

  var body: some Scene {
    WindowGroup {
      RootView(options: options)
    }
  }
}

/// The settings screen and its two diagnostic screens, in the chosen language and direction.
struct RootView: View {
  private let clock: AppClock
  @State private var store: SettingsStore

  init(options: LaunchOptions) {
    clock = AppClock(start: options.now, frozen: options.frozen)
    _store = State(initialValue: SettingsStore(options: options))
  }

  var body: some View {
    let strings = WidgetStrings(language: store.settings?.language ?? .device)
    NavigationStack {
      SettingsView(store: store, strings: strings, clock: clock)
        .navigationDestination(for: Screen.self) { screen in
          switch screen {
          case .states: WidgetStatesView(strings: strings, clock: clock)
          case .log: WidgetLogView(strings: strings)
          }
        }
    }
    .environment(\.locale, strings.locale)
    .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
  }
}

/// The screens the settings screen links to.
enum Screen: Hashable {
  case states
  case log
}
