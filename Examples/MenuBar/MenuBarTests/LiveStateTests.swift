import Foundation
import SalahWidgets
import Testing

@testable import MenuBar

/// The live-state pattern in the app: publish what plays, act on the stop signal, republish.
/// (The stop harness proves the same across processes, against the running app.)
@Suite("Live state", .serialized)
@MainActor
struct LiveStateTests {
  let player = FakeTonePlayer()
  let recorder = ReloadRecorder()
  let storage: SharedValue<NowPlaying>
  let signal = TestStorage.signal()
  let diagnostics = Diagnostics(storage: nil)
  let live: LiveState

  init() {
    storage = TestStorage.nowPlaying(recorder)
    live = LiveState(
      player: player, storage: storage, signal: signal, widgetKinds: ["prayers"],
      diagnostics: diagnostics)
  }

  var events: [DiagnosticsRecord.Event] { diagnostics.records.map(\.event) }

  @Test("starting publishes that nothing plays, clearing a value an earlier run left")
  func startClearsAStaleValue() throws {
    try storage.save(NowPlaying(alert: nil, startedAt: .distantPast))
    live.start()
    #expect(live.isObservingStopSignal)
    #expect(storage.load() == nil)
    #expect(recorder.reloads == [["prayers"]])
    #expect(diagnostics.records.last?.detail == "playing=false changed=true")
  }

  @Test("playing publishes what plays and reloads the widget")
  func playPublishes() throws {
    live.start()
    let alert = NowPlaying.Alert(prayer: .asr, observance: .ordinary, kind: .atTime)
    live.play(alert, cycles: 3)
    #expect(player.plays == [3])
    #expect(live.nowPlaying?.alert == alert)
    #expect(storage.load() == live.nowPlaying)
    #expect(recorder.reloads == [["prayers"]])
    #expect(events == [.launched, .published, .started, .published])
  }

  @Test("the stop signal stops the tone and republishes")
  func stopSignal() async throws {
    live.start()
    live.play(nil, cycles: nil)
    // What the widget's intent does in the extension's process.
    StopRequest.send(nowPlaying: storage, signal: signal)
    #expect(await eventually { live.nowPlaying == nil })
    #expect(player.isPlaying == false)
    #expect(storage.load() == nil)
    #expect(events.suffix(3) == [.stopSignal, .stopped, .published])
    #expect(
      diagnostics.records.last(where: { $0.event == .stopped })?.detail == "signal wasPlaying=true")
  }

  /// The intent's cleared value can reach the app after the signal does. The app must stop on
  /// the signal anyway, and its republish then clears the stale value itself.
  @Test("the app acts on the signal, not on the stored value")
  func signalWithAStaleValue() async throws {
    live.start()
    live.play(nil, cycles: nil)
    #expect(storage.load() != nil, "the stored value still says the tone plays")
    #expect(signal.post())
    #expect(await eventually { live.nowPlaying == nil })
    #expect(player.isPlaying == false)
    #expect(storage.load() == nil, "the republish clears the value the intent hadn't")
    #expect(diagnostics.records.last?.detail == "playing=false changed=true")
  }

  @Test("a cleared value without the signal doesn't stop the tone")
  func clearedValueAlone() async throws {
    live.start()
    live.play(nil, cycles: nil)
    try storage.save(nil)
    try await Task.sleep(for: .milliseconds(300))
    #expect(player.isPlaying)
    #expect(live.nowPlaying != nil)
  }

  @Test("a tone that ends by itself publishes that nothing plays")
  func finished() throws {
    live.start()
    live.play(nil, cycles: 1)
    player.finish()
    #expect(live.nowPlaying == nil)
    #expect(storage.load() == nil)
    #expect(events.suffix(2) == [.finished, .published])
  }

  @Test("the app's own Stop button stops and publishes")
  func appStop() throws {
    live.start()
    live.play(nil, cycles: nil)
    live.stop()
    #expect(player.isPlaying == false)
    #expect(storage.load() == nil)
    #expect(
      diagnostics.records.last(where: { $0.event == .stopped })?.detail == "app wasPlaying=true")
  }

  @Test("a tone that can't start publishes nothing playing")
  func playbackFailure() throws {
    live.start()
    player.failsNextPlay = true
    live.play(nil, cycles: 1)
    #expect(live.nowPlaying == nil)
    #expect(storage.load() == nil)
    #expect(events.contains(.playbackFailed))
  }

  @Test("an unchanged value reloads nothing")
  func gatedReloads() throws {
    live.start()
    live.stop()
    live.stop()
    #expect(recorder.reloads.isEmpty)
  }

  @Test("the diagnostics log keeps the last records of this launch")
  func diagnosticsCapacity() {
    var log = DiagnosticsLog(launchID: "test", records: [])
    for _ in 0..<(DiagnosticsLog.capacity + 5) {
      log = log.appending(.published, at: Date())
    }
    #expect(log.records.count == DiagnosticsLog.capacity)
    #expect(log.records.first?.sequence == 6)
  }
}
