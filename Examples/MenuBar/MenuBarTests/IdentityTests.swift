import Foundation
import Testing

@testable import MenuBar

/// The App Group the code opens is the one the build names (APP_GROUP_IDENTIFIER).
///
/// With the example's own identifiers, the group the build names is the one the code falls
/// back to, so CI also runs these tests and the round trip under other identifiers: there, a
/// process that didn't take the group from the build would open a different one.
struct IdentityTests {
  /// The build writes the group into the host app's Info.plist, and the shared code opens the
  /// group named there.
  @Test("the code opens the App Group the build names")
  func appGroupComesFromTheBuild() throws {
    let named = try #require(
      Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
    #expect(!named.isEmpty && !named.contains("$("))
    #expect(MenuBarID.appGroup == named)
  }

  /// The widget extension reads the group from its own Info.plist. Without the key it would
  /// open the example's own group, whatever its entitlements grant. (The round trip covers the
  /// stop harness: it reads what the app stored.)
  @Test("the widget extension is told the same App Group")
  func theWidgetExtensionNamesTheSameGroup() throws {
    let plugIns = try #require(Bundle.main.builtInPlugInsURL)
    let widgets = try #require(Bundle(url: plugIns.appending(path: "MenuBarWidgets.appex")))
    #expect(
      widgets.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String == MenuBarID.appGroup)
  }
}
