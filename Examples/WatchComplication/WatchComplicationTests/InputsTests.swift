import Foundation
import SalahCalculation
import SalahCore
import SalahWidgets
import Testing

@testable import WatchComplicationWatch

/// The widget kinds a shared value asked to reload, recorded from any thread.
///
/// `@unchecked Sendable`: every access to `kinds` holds `lock`.
nonisolated final class ReloadRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var kinds: [[String]] = []

  func record(_ widgetKinds: [String]) {
    lock.withLock { kinds.append(widgetKinds) }
  }

  var requests: [[String]] {
    lock.withLock { kinds }
  }
}

/// The inputs' coding, the application context, the presets and the launch arguments.
struct InputsTests {
  static let now = TimelineTests.makkahAfternoon

  @Test(arguments: InputsPreset.allCases)
  func inputsSurviveAJSONRoundTrip(_ preset: InputsPreset) throws {
    let inputs = preset.inputs(today: Self.now)
    let decoded = try JSONDecoder().decode(WatchInputs.self, from: inputs.encoded())
    #expect(decoded == inputs)
    #expect(decoded.fingerprint == inputs.fingerprint)
    #expect(inputs.fingerprint.count == 16)
  }

  @Test func differentInputsHaveDifferentFingerprints() {
    let fingerprints = Set(InputsPreset.allCases.map { $0.inputs(today: Self.now).fingerprint })
    #expect(fingerprints.count == InputsPreset.allCases.count)
    #expect(
      InputsPreset.makkah.inputs(today: Self.now).fingerprint
        == InputsPreset.makkah.inputs(today: Self.now.addingTimeInterval(86_400)).fingerprint)
  }

  @Test func theContextCarriesTheInputsAndTheSendTime() throws {
    let message = InputsMessage(
      inputs: InputsPreset.mosque.inputs(today: Self.now), sentAt: Self.now)
    let context = try message.context()
    #expect(context[InputsMessage.inputsKey] is Data)
    #expect(try InputsMessage(context: context) == message)
  }

  @Test func contextsWithoutUsableInputsAreRejected() {
    #expect(throws: InputsMessage.DecodingProblem.missingInputs) {
      try InputsMessage(context: [:])
    }
    #expect(throws: InputsMessage.DecodingProblem.missingInputs) {
      try InputsMessage(context: ["inputs.v0": Data()])
    }
    #expect {
      try InputsMessage(context: [InputsMessage.inputsKey: Data("{}".utf8)])
    } throws: { error in
      if case .undecodable = error as? InputsMessage.DecodingProblem { return true }
      return false
    }
  }

  @Test func theMosquePresetRunsOutAndTheEndedPresetHasEnded() {
    let zone = InputsPreset.mosqueLocation.timeZone
    let today = CivilDay(containing: Self.now, in: zone)
    let mosque = InputsPreset.mosque.inputs(today: Self.now)
    let ended = InputsPreset.mosqueEnded.inputs(today: Self.now)
    guard case .timetable(let rows) = mosque.source, case .timetable(let old) = ended.source else {
      Issue.record("The mosque presets aren't timetables")
      return
    }
    #expect(rows.rows.map(\.day) == [today, today.adding(days: 1), today.adding(days: 2)])
    #expect(old.lastDay == today.adding(days: -1))
    // Every row publishes all six times, as local wall-clock times.
    for row in rows.rows + old.rows {
      #expect(Set(row.times.keys) == Set(PrayerKind.allCases))
    }
    // The published times are the calculation's, to the minute.
    let day = mosque.schedule.day(today).day
    #expect(day?.events.count == 6)
    let calculated = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
      .prayerDay(today, at: InputsPreset.mosqueLocation).day
    for (published, computed) in zip(day?.events ?? [], calculated?.events ?? []) {
      #expect(abs(published.time.timeIntervalSince(computed.time)) < 60)
    }
  }

  @Test func launchArgumentsAreRead() {
    let options = LaunchOptions(arguments: [
      "app", "-now", "2026-10-14T14:00:00+03:00", "-language", "ar", "-preset", "mosqueEnded",
      "-resetInputs", "-send", "-screen", "states",
    ])
    #expect(options.now == Self.now)
    #expect(options.date() == Self.now)
    #expect(options.language == "ar")
    #expect(options.preset == .mosqueEnded)
    #expect(options.resetInputs)
    #expect(options.send)
    #expect(options.screen == "states")

    let plain = LaunchOptions(arguments: ["app", "-preset", "nowhere", "-now", "yesterday"])
    #expect(plain.preset == nil)
    #expect(plain.now == nil)
    #expect(!plain.resetInputs)
  }

  @Test func theCatalogHasArabicStrings() {
    let english = AppStrings(language: "en")
    let arabic = AppStrings(language: "ar")
    #expect(english("No settings yet") == "No settings yet")
    #expect(arabic("No settings yet") != english("No settings yet"))
    #expect(arabic("Timetable ended") != english("Timetable ended"))
    #expect(arabic.isRightToLeft)
    #expect(arabic.names.name(of: .fajr) == "الفجر")
  }
}

/// The receive-and-store path: a received context saved through `SharedValue`, with the
/// complication reloaded only when the inputs change.
struct ReceiverTests {
  let suite = "test.\(UUID().uuidString)"
  let recorder = ReloadRecorder()
  let now = TimelineTests.makkahAfternoon

  private var receiver: InputsReceiver {
    let recorder = recorder
    return InputsReceiver(
      inputs: SharedValue(appGroup: suite, key: "inputs.v1") { recorder.record($0) },
      receipt: SharedValue(appGroup: suite, key: "receipt.v1") { recorder.record($0) })
  }

  private func context(_ preset: InputsPreset, sentAt: Date) throws -> [String: Any] {
    try InputsMessage(inputs: preset.inputs(today: now), sentAt: sentAt).context()
  }

  @Test func receivedInputsAreStoredAndReloadOnlyWhenTheyChange() throws {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let receiver = receiver
    let makkah = InputsPreset.makkah.inputs(today: now)

    // The first inputs: stored, and the complication reloads.
    #expect(
      receiver.receive(context: try context(.makkah, sentAt: now), at: now)
        == .stored(changed: true))
    #expect(receiver.inputs.load() == makkah)
    #expect(recorder.requests == [[WatchStorage.complicationKind]])
    #expect(receiver.receipt.load()?.changed == true)
    #expect(receiver.receipt.load()?.origin == .companion)

    // The same inputs sent again: a new receipt, no reload.
    let later = now.addingTimeInterval(60)
    #expect(
      receiver.receive(context: try context(.makkah, sentAt: later), at: later)
        == .stored(changed: false))
    #expect(recorder.requests.count == 1)
    #expect(receiver.receipt.load()?.changed == false)
    #expect(receiver.receipt.load()?.sentAt == later)

    // The same send read again, as the session's last context is at launch: nothing changes.
    #expect(
      receiver.receive(context: try context(.makkah, sentAt: later), at: later) == .alreadyReceived)
    #expect(recorder.requests.count == 1)

    // Different inputs: stored, and the complication reloads.
    let mosque = InputsPreset.mosqueEnded.inputs(today: now)
    #expect(
      receiver.receive(context: try context(.mosqueEnded, sentAt: later + 60), at: later + 60)
        == .stored(changed: true))
    #expect(receiver.inputs.load() == mosque)
    #expect(recorder.requests.count == 2)
    #expect(receiver.receipt.load()?.fingerprint == mosque.fingerprint)
  }

  @Test func aContextThatDoesntDecodeKeepsTheLastValidInputs() throws {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let receiver = receiver
    _ = receiver.receive(context: try context(.makkah, sentAt: now), at: now)
    let outcome = receiver.receive(
      context: [InputsMessage.inputsKey: Data("not json".utf8), InputsMessage.sentAtKey: now + 5],
      at: now + 5)
    guard case .rejected = outcome else {
      Issue.record("A broken context was accepted: \(outcome)")
      return
    }
    #expect(receiver.inputs.load() == InputsPreset.makkah.inputs(today: now))
    #expect(recorder.requests.count == 1)
  }

  @Test func storedInputsAreReadBackByANewReader() throws {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    _ = receiver.receive(context: try context(.mosque, sentAt: now), at: now)
    // Another value over the same suite and key, as the complication extension holds.
    let reader = SharedValue<WatchInputs>(appGroup: suite, key: "inputs.v1")
    #expect(reader.load() == InputsPreset.mosque.inputs(today: now))
  }

  @Test func launchArgumentPresetsUseTheSamePath() {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let receiver = receiver
    let message = InputsMessage(inputs: InputsPreset.makkah.inputs(today: now), sentAt: now)
    #expect(receiver.store(message, origin: .launchArguments, at: now) == .stored(changed: true))
    #expect(receiver.receipt.load()?.origin == .launchArguments)
    #expect(recorder.requests == [[WatchStorage.complicationKind]])
  }

  @Test func resettingRemovesTheInputsAndReloads() throws {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let receiver = receiver
    _ = receiver.receive(context: try context(.makkah, sentAt: now), at: now)
    receiver.reset()
    #expect(receiver.inputs.load() == nil)
    #expect(receiver.receipt.load() == nil)
    #expect(recorder.requests.count == 2)
    // Resetting again changes nothing and reloads nothing.
    receiver.reset()
    #expect(recorder.requests.count == 2)
  }
}
