import Foundation
import SalahCalculation
import SalahWidgets
import Testing
import os

@testable import PhoneWidgets

/// The stored settings, the reload gating the app shows, the launch arguments and the
/// diagnostics log.
@MainActor
struct SettingsTests {
  /// A shared value in its own defaults suite, recording the reloads it asks for.
  final class Recorder: Sendable {
    let suite = "PhoneWidgetsTests.\(UUID().uuidString)"
    private let kinds = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    var reloads: [[String]] { kinds.withLock { $0 } }

    var shared: SharedValue<WidgetSettings> {
      SharedValue(appGroup: suite, key: "settings.v1") { [self] widgetKinds in
        kinds.withLock { $0.append(widgetKinds) }
      }
    }

    deinit {
      UserDefaults().removePersistentDomain(forName: suite)
    }
  }

  @Test func settingsRoundTripThroughJSON() throws {
    var settings = WidgetSettings(place: .tromso, method: .karachi, language: .arabic)
    settings.calculation.parameters.madhab = .hanafi
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(WidgetSettings.self, from: data) == settings)
  }

  @Test func theFingerprintIsStableAndFollowsTheValue() {
    let settings = WidgetSettings.defaults
    #expect(settings.fingerprint == WidgetSettings.defaults.fingerprint)
    #expect(settings.fingerprint.count == 16)
    var arabic = settings
    arabic.language = .arabic
    #expect(arabic.fingerprint != settings.fingerprint)
    #expect(arabic.summary == "makkah · ummAlQura · ar")
  }

  @Test func choosingAMethodReplacesTheParameters() {
    var settings = WidgetSettings.defaults
    settings.choose(.muslimWorldLeague)
    #expect(settings.method == .muslimWorldLeague)
    #expect(settings.calculation == CalculationSettings(method: .muslimWorldLeague))
  }

  @Test func aChangedSaveRequestsAReloadAndAnUnchangedOneDoesNot() throws {
    let recorder = Recorder()
    let store = SettingsStore(shared: recorder.shared, options: LaunchOptions())
    #expect(store.settings == nil)
    #expect(store.lastSave == nil)

    store.update { _ in }
    #expect(store.lastSave == .reloadRequested)
    #expect(store.settings == .defaults)
    #expect(recorder.shared.load() == .defaults)
    #expect(recorder.reloads == [[PhoneWidgetsID.widgetKind]])

    store.saveAgain()
    #expect(store.lastSave == .unchanged)
    #expect(store.saveCount == 2)
    #expect(recorder.reloads.count == 1)

    store.update { $0.language = .arabic }
    #expect(store.lastSave == .reloadRequested)
    #expect(recorder.reloads.count == 2)
    #expect(recorder.shared.load()?.language == .arabic)

    store.update { $0.language = .arabic }
    #expect(store.lastSave == .unchanged)
    #expect(recorder.reloads.count == 2)
  }

  @Test func launchArgumentsChangeAndCleanStartRemovesTheSettings() {
    let recorder = Recorder()
    let options = LaunchOptions(arguments: [
      "PhoneWidgets", "-place", "tromso", "-method", "egyptian", "-language", "ar",
    ])
    let store = SettingsStore(shared: recorder.shared, options: options)
    #expect(store.settings?.place == .tromso)
    #expect(store.settings?.method == .egyptian)
    #expect(store.settings?.language == .arabic)
    #expect(store.lastSave == .reloadRequested)

    let clean = SettingsStore(
      shared: recorder.shared, options: LaunchOptions(arguments: ["PhoneWidgets", "-cleanStart"]))
    #expect(clean.settings == nil)
    #expect(recorder.shared.load() == nil)
    // Removing stored settings is a change, so the widget reloads into its setup prompt.
    #expect(recorder.reloads.count == 2)
  }

  @Test func unreadableArgumentsAreIgnored() {
    let options = LaunchOptions(arguments: [
      "PhoneWidgets", "-place", "atlantis", "-method", "nope", "-language", "fr", "-now", "soon",
    ])
    #expect(options == LaunchOptions())
    #expect(options.changesSettings == false)
  }

  @Test func theClockStartsAtNowAndCanBeFrozen() throws {
    let start = try Date("2026-10-14T14:00:00+03:00", strategy: .iso8601)
    let launch = Date(timeIntervalSince1970: 0)
    let running = AppClock(start: start, launch: launch)
    #expect(running.now(at: launch.addingTimeInterval(60)) == start.addingTimeInterval(60))
    let frozen = AppClock(start: start, launch: launch, frozen: true)
    #expect(frozen.now(at: launch.addingTimeInterval(60)) == start)
  }

  // MARK: Diagnostics

  @Test func theLogRecordsEachCallAndKeepsTheLast200() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("diagnostics-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let log = DiagnosticsLog(fileURL: file)
    let settings = WidgetSettings(place: .makkah, method: .ummAlQura, language: .arabic)
    let now = Date(timeIntervalSince1970: 1_791_975_600)

    let timeline = TimelineDiagnostics.timeline(
      settings: settings, now: now, family: "systemMedium", deviceLanguage: .english, log: log)
    let record = try #require(log.load().last)
    #expect(record.sequence == 1)
    #expect(record.callDate == now)
    #expect(record.settingsFingerprint == settings.fingerprint)
    #expect(record.fajrName == "الفجر")
    #expect(record.localeIdentifier.hasPrefix("ar"))
    #expect(record.entryCount == timeline.entries.count)
    #expect(record.entries.count == timeline.entries.count)
    #expect(record.validUntil == now.addingTimeInterval(48 * 3_600))
    #expect(record.reloadDate == now.addingTimeInterval(24 * 3_600))
    #expect(record.isTruncated == false)
    #expect(record.states.hasSuffix("expired 1 · setup 0"))
    #expect(record.entries.first == "2026-10-14 14:00 next asr@15:27")
    #expect(record.generationMilliseconds > 0)
    #expect(record.footprintBefore != nil)

    _ = TimelineDiagnostics.timeline(
      settings: nil, now: now, family: "systemSmall", deviceLanguage: .english, log: log)
    let setup = try #require(log.load().last)
    #expect(setup.settingsFingerprint == "none")
    #expect(setup.fajrName == "Fajr")
    #expect(setup.states == "available 0 · partial 0 · unavailable 0 · expired 0 · setup 1")
    #expect(setup.validUntil == nil)

    for _ in 0..<(DiagnosticsLog.capacity + 5) {
      log.append { record.with(sequence: $0) }
    }
    let records = log.load()
    #expect(records.count == DiagnosticsLog.capacity)
    #expect(records.last?.sequence == DiagnosticsLog.capacity + 7)
    #expect(records.map(\.sequence) == Array(8...(DiagnosticsLog.capacity + 7)))
  }

  @Test func theFootprintIsMeasured() throws {
    let footprint = try #require(MemoryFootprint.current())
    #expect(footprint > 1_000_000)
  }
}

extension DiagnosticsRecord {
  fileprivate func with(sequence: Int) -> DiagnosticsRecord {
    var copy = self
    copy.sequence = sequence
    return copy
  }
}
