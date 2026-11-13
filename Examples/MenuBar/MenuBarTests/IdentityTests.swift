import Foundation
import Testing

@testable import MenuBar

/// The App Group the code opens is the one the build names (APP_GROUP_IDENTIFIER).
struct IdentityTests {
  /// The build writes the group into the host app's Info.plist, as it does into the widget
  /// extension's and the stop harness's, and the shared code opens the group named there: with
  /// your own group in Config/Local.xcconfig, every process opens yours.
  @Test("the code opens the App Group the build names")
  func appGroupComesFromTheBuild() throws {
    let named = try #require(
      Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
    #expect(!named.isEmpty && !named.contains("$("))
    #expect(MenuBarID.appGroup == named)
  }
}
