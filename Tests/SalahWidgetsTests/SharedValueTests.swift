import Foundation
import Testing

@testable import SalahWidgets

/// A settings value like an app's.
nonisolated private struct Settings: Codable, Equatable, Sendable {
  var method: String
  var offset: Double
}

/// Records the widget kinds a shared value asks to reload.
nonisolated private final class ReloadLog: Sendable {
  private let lock = NSLock()
  nonisolated(unsafe) private var calls: [[String]] = []

  func record(_ kinds: [String]) {
    lock.withLock { calls.append(kinds) }
  }

  var all: [[String]] { lock.withLock { calls } }
}

/// A shared value in a fresh suite of its own, removed when the test ends.
private struct Fixture: ~Copyable {
  let suite = "io.github.salah-kit.tests.shared-value.\(UUID().uuidString)"
  let log = ReloadLog()

  func value(key: String = "settings.v1") -> SharedValue<Settings> {
    let log = log
    return SharedValue(appGroup: suite, key: key) { log.record($0) }
  }

  var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

  deinit {
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}

@Suite("SharedValue")
struct SharedValueTests {
  @Test("loads nil when nothing is stored")
  func loadsNilWhenEmpty() {
    let fixture = Fixture()
    #expect(fixture.value().load() == nil)
  }

  @Test("saves, loads and reloads once for a new value")
  func savesNewValue() throws {
    let fixture = Fixture()
    let shared = fixture.value()
    let settings = Settings(method: "ummAlQura", offset: 1.5)

    #expect(try shared.save(settings, reloading: ["prayers", "next"]))
    #expect(shared.load() == settings)
    #expect(fixture.log.all == [["prayers", "next"]])
  }

  @Test("an unchanged value isn't written again and reloads nothing")
  func gatesUnchangedValue() throws {
    let fixture = Fixture()
    let shared = fixture.value()
    let settings = Settings(method: "ummAlQura", offset: 1.5)
    try shared.save(settings, reloading: ["prayers"])
    // A marker the encoder never writes: if the unchanged save rewrote the data, it would go.
    let stored = try #require(fixture.defaults?.data(forKey: "settings.v1"))
    let marked = stored.replacingOccurrences(of: "1.5", with: "1.50")
    fixture.defaults?.set(marked, forKey: "settings.v1")

    #expect(try shared.save(settings, reloading: ["prayers"]) == false)
    #expect(fixture.defaults?.data(forKey: "settings.v1") == marked)
    #expect(fixture.log.all == [["prayers"]])
  }

  @Test("a changed value is written and reloads")
  func reloadsChangedValue() throws {
    let fixture = Fixture()
    let shared = fixture.value()
    try shared.save(Settings(method: "ummAlQura", offset: 0), reloading: ["prayers"])

    #expect(try shared.save(Settings(method: "ummAlQura", offset: 1), reloading: ["prayers"]))
    #expect(shared.load() == Settings(method: "ummAlQura", offset: 1))
    #expect(fixture.log.all == [["prayers"], ["prayers"]])
  }

  @Test("a change with no widget kinds reloads nothing")
  func changeWithoutKinds() throws {
    let fixture = Fixture()
    #expect(try fixture.value().save(Settings(method: "isna", offset: 0)))
    #expect(fixture.log.all.isEmpty)
  }

  @Test("saving nil removes the value once")
  func removesValue() throws {
    let fixture = Fixture()
    let shared = fixture.value()
    try shared.save(Settings(method: "isna", offset: 0), reloading: ["prayers"])

    #expect(try shared.save(nil, reloading: ["prayers"]))
    #expect(shared.load() == nil)
    #expect(fixture.defaults?.object(forKey: "settings.v1") == nil)
    #expect(try shared.save(nil, reloading: ["prayers"]) == false)
    #expect(fixture.log.all == [["prayers"], ["prayers"]])
  }

  @Test("stored data that doesn't decode reads as nil and counts as a change")
  func undecodableData() throws {
    let fixture = Fixture()
    let shared = fixture.value()
    fixture.defaults?.set(Data("{\"method\": 3}".utf8), forKey: "settings.v1")

    #expect(shared.load() == nil)
    #expect(try shared.save(Settings(method: "isna", offset: 0), reloading: ["prayers"]))
    #expect(shared.load() == Settings(method: "isna", offset: 0))
    #expect(fixture.log.all == [["prayers"]])
  }

  @Test("a value that can't be encoded throws, writes nothing and reloads nothing")
  func encodingFailure() throws {
    let fixture = Fixture()
    let shared = fixture.value()
    try shared.save(Settings(method: "isna", offset: 0), reloading: ["prayers"])

    #expect {
      try shared.save(Settings(method: "isna", offset: .nan), reloading: ["prayers"])
    } throws: { error in
      guard case .encodingFailed = error as? SharedValueError else { return false }
      return true
    }
    #expect(shared.load() == Settings(method: "isna", offset: 0))
    #expect(fixture.log.all == [["prayers"]])
  }

  @Test(
    "a suite UserDefaults refuses throws",
    .enabled(if: UserDefaults(suiteName: "NSGlobalDomain") == nil))
  func unavailableSuite() {
    let log = ReloadLog()
    let shared = SharedValue<Settings>(appGroup: "NSGlobalDomain", key: "settings.v1") {
      log.record($0)
    }
    #expect(throws: SharedValueError.appGroupUnavailable("NSGlobalDomain")) {
      try shared.save(Settings(method: "isna", offset: 0), reloading: ["prayers"])
    }
    #expect(log.all.isEmpty)
  }

  @Test("values under different keys are independent")
  func keysAreIndependent() throws {
    let fixture = Fixture()
    let first = fixture.value(key: "first.v1")
    let second = fixture.value(key: "second.v1")
    try first.save(Settings(method: "isna", offset: 0))

    #expect(second.load() == nil)
    #expect(try second.save(Settings(method: "isna", offset: 0)))
  }

  @Test("another SharedValue for the same group and key sees the value")
  func sameGroupAndKey() throws {
    let fixture = Fixture()
    try fixture.value().save(Settings(method: "mwl", offset: 2))
    let reader = SharedValue<Settings>(appGroup: fixture.suite, key: "settings.v1")
    #expect(reader.load() == Settings(method: "mwl", offset: 2))
  }

  @Test("the product ships a privacy manifest declaring the App Group reason 1C8F.1")
  func privacyManifest() throws {
    let url = try #require(
      Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    let plist = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: url), format: nil)
    let manifest = try #require(plist as? [String: Any])
    let types = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    #expect(types.count == 1)
    #expect(
      types.first?["NSPrivacyAccessedAPIType"] as? String
        == "NSPrivacyAccessedAPICategoryUserDefaults")
    #expect(types.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["1C8F.1"])
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
  }
}

extension Data {
  /// The data with every occurrence of one UTF-8 string replaced by another.
  fileprivate func replacingOccurrences(of target: String, with replacement: String) -> Data {
    Data(
      String(decoding: self, as: UTF8.self).replacingOccurrences(of: target, with: replacement).utf8
    )
  }
}
