import SwiftUI

@main
struct CalculatedPhoneApp: App {
  private let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

  var body: some Scene {
    WindowGroup {
      RootView(options: options)
    }
  }
}

/// The main screen and its settings sheet, in the chosen language and direction.
struct RootView: View {
  private let strings: PhoneStrings
  private let clock: AppClock
  @State private var store: SettingsStore
  @State private var showsSettings = false

  init(options: LaunchOptions) {
    strings = PhoneStrings(language: options.language)
    clock = AppClock(start: options.now, frozen: options.frozen)
    _store = State(initialValue: SettingsStore(options: options))
  }

  var body: some View {
    NavigationStack {
      TodayView(settings: store.settings, clock: clock, strings: strings)
        .navigationTitle(Text(verbatim: strings("Prayer times")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button {
              showsSettings = true
            } label: {
              Label {
                Text(verbatim: strings("Settings"))
              } icon: {
                Image(systemName: "gearshape")
              }
            }
            .accessibilityIdentifier("settings.open")
          }
        }
    }
    .sheet(isPresented: $showsSettings) {
      SettingsView(store: store, strings: strings)
        .environment(\.locale, strings.locale)
        .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
    }
    .environment(\.locale, strings.locale)
    .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
  }
}
