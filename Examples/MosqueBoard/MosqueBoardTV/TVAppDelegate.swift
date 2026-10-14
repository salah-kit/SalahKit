import UIKit

/// Keeps the board on the TV: nobody touches a mosque's TV, so the screen saver would hide the
/// board after a few minutes without input.
@MainActor
final class TVAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    application.isIdleTimerDisabled = true
    return true
  }
}
