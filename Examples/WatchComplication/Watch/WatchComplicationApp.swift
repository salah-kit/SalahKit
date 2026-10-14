import SwiftUI

@main
struct WatchComplicationApp: App {
  @State private var model = WatchModel(
    options: LaunchOptions(arguments: ProcessInfo.processInfo.arguments))

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
    }
    // The system wakes the app in the background to deliver an application context that
    // arrived while it wasn't running; the delegate stores it.
    .backgroundTask(.watchConnectivity) {
      await model.finishPendingTransfers()
    }
  }
}

/// The home screen, in the chosen language and direction, with the states and diagnostics
/// screens a tap away.
struct RootView: View {
  let model: WatchModel
  @State private var path: [Screen] = []

  /// A screen under the home screen.
  enum Screen: String, Hashable {
    case states
    case diagnostics
  }

  var body: some View {
    NavigationStack(path: $path) {
      HomeView(model: model)
        .navigationDestination(for: Screen.self) { screen in
          switch screen {
          case .states: StatesView(model: model)
          case .diagnostics: DiagnosticsView(model: model)
          }
        }
    }
    .environment(\.locale, model.strings.locale)
    .environment(\.layoutDirection, model.strings.isRightToLeft ? .rightToLeft : .leftToRight)
    .onAppear {
      if path.isEmpty, let screen = model.options.screen.flatMap(Screen.init(rawValue:)) {
        path = [screen]
      }
    }
  }
}
