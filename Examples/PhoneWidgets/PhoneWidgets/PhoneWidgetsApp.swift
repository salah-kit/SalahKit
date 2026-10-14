import SwiftUI

@main
struct PhoneWidgetsApp: App {
  private let clock: AppClock
  @State private var store: SettingsStore

  // The store is made here, once per launch: its initializer applies the launch arguments and
  // saves. Made in a view's initializer, it would run again each time SwiftUI rebuilds the
  // view, and a discarded store would save the launch arguments over the user's later changes.
  init() {
    let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    clock = AppClock(start: options.now, frozen: options.frozen)
    _store = State(initialValue: SettingsStore(options: options))
  }

  var body: some Scene {
    WindowGroup {
      RootView(store: store, clock: clock)
    }
  }
}

/// The settings screen and its two diagnostic screens, in the chosen language and direction.
struct RootView: View {
  let store: SettingsStore
  let clock: AppClock

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
