import Testing
import UIKit

/// What only the tvOS app does. The tests are hosted by the app, so it has finished launching.
@MainActor
struct TVAppTests {
  /// Nobody touches a mosque's TV: without this, the screen saver hides the board.
  @Test func theScreenSaverStaysOff() {
    #expect(UIApplication.shared.isIdleTimerDisabled)
  }
}
