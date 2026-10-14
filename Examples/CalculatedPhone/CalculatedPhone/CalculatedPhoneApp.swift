import SwiftUI
import UserNotifications

@main
struct CalculatedPhoneApp: App {
  private let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
  /// Shows notifications that arrive while the app is in front.
  private let presenter = NotificationPresenter()

  init() {
    UNUserNotificationCenter.current().delegate = presenter
  }

  var body: some Scene {
    WindowGroup {
      RootView(options: options)
    }
  }
}

/// The main screen and its settings sheet, in the chosen language and direction.
///
/// Alerts are replanned when the app becomes active and whenever the settings change.
struct RootView: View {
  private let strings: PhoneStrings
  private let clock: AppClock
  @State private var store: SettingsStore
  @State private var alerts: AlertCoordinator
  @State private var showsSettings = false
  @Environment(\.scenePhase) private var scenePhase

  init(options: LaunchOptions) {
    strings = PhoneStrings(language: options.language)
    clock = AppClock(start: options.now, frozen: options.frozen)
    _store = State(initialValue: SettingsStore(options: options))
    _alerts = State(initialValue: AlertCoordinator(options: options))
  }

  var body: some View {
    NavigationStack {
      TodayView(settings: store.settings, clock: clock, strings: strings, alerts: alerts)
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
    .task(id: store.settings) {
      await alerts.replan(settings: store.settings, strings: strings)
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await alerts.replan(settings: store.settings, strings: strings) }
    }
    .sheet(isPresented: $showsSettings) {
      SettingsView(store: store, alerts: alerts, strings: strings)
        .environment(\.locale, strings.locale)
        .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
    }
    .environment(\.locale, strings.locale)
    .environment(\.layoutDirection, strings.isRightToLeft ? .rightToLeft : .leftToRight)
  }
}
