import AVFoundation
import Foundation
import Testing

@testable import MenuBar

@Suite("Tone")
struct ToneTests {
  @Test("the chime is a valid 16-bit mono WAV of one cycle")
  func wav() throws {
    let data = ToneSynthesis.wav()
    #expect(data.prefix(4) == Data("RIFF".utf8))
    #expect(data.subdata(in: 8..<12) == Data("WAVE".utf8))
    let samples = Int((ToneSynthesis.cycleSeconds * Double(ToneSynthesis.sampleRate)).rounded())
    #expect(abs(data.count - 44 - samples * 2) <= 4)
    let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
    #expect(abs(player.duration - ToneSynthesis.cycleSeconds) < 0.01)
  }

  @Test("the notes sound, stay within full scale, and the pause is silent")
  func samples() {
    let samples = ToneSynthesis.samples()
    #expect(samples.allSatisfy { abs($0) <= 1 })
    #expect((samples.map(abs).max() ?? 0) > 0.3)
    let pause = Int(ToneSynthesis.pauseSeconds * Double(ToneSynthesis.sampleRate))
    #expect(samples.suffix(pause).allSatisfy { $0 == 0 })
  }
}

@Suite("Launch options")
struct LaunchOptionsTests {
  @Test("every argument is read")
  func arguments() throws {
    let options = LaunchOptions(arguments: [
      "MenuBar", "-now", "2026-10-14T12:00:00+03:00", "-place", "london", "-method", "isna",
      "-language", "ar", "-alerts", "on", "-reminder", "15", "-tone", "off", "-notifications",
      "memory", "-muted", "-playTestTone", "repeating", "-showWindow", "-testEvents",
    ])
    #expect(options.now == (try Date("2026-10-14T12:00:00+03:00", strategy: .iso8601)))
    #expect(options.place == .london)
    #expect(options.method == .isna)
    #expect(options.language == .arabic)
    #expect(options.alertsEnabled == true)
    #expect(options.reminderMinutes == .some(15))
    #expect(options.playsTone == false)
    #expect(options.inMemoryNotifications)
    #expect(options.muted)
    #expect(options.testTone == .repeating)
    #expect(options.showWindow)
    #expect(options.acceptsTestEvents)

    let settings = options.applied(to: .defaults)
    #expect(settings.place == .london)
    #expect(settings.method == .isna)
    #expect(settings.language == .arabic)
    #expect(
      settings.alerts == AlertPreferences(enabled: true, reminderMinutes: 15, playsTone: false))
  }

  @Test("unreadable values are ignored, and -reminder off removes the reminder")
  func ignoredValues() {
    let options = LaunchOptions(arguments: [
      "MenuBar", "-now", "noon", "-place", "atlantis", "-reminder", "off", "-alerts", "maybe",
    ])
    #expect(options.now == nil)
    #expect(options.place == nil)
    #expect(options.alertsEnabled == nil)
    #expect(options.applied(to: .defaults).alerts.reminderMinutes == nil)
    #expect(LaunchOptions(arguments: ["-reminder", "500"]).reminderMinutes == nil)
    // Only the reminders the dropdown offers, so its picker always shows the choice.
    #expect(LaunchOptions(arguments: ["-reminder", "20"]).reminderMinutes == nil)
    #expect(LaunchOptions(arguments: ["-tone", "maybe"]).playsTone == nil)
  }

  /// A journey adds its own arguments after the quiet launch's (`-language en`, `-alerts off`);
  /// reading the first occurrence once made the Arabic journey show English.
  @Test("when an argument is given twice, the later one wins")
  func laterArgumentsWin() {
    let options = LaunchOptions(arguments: [
      "MenuBar", "-language", "en", "-alerts", "off", "-language", "ar", "-alerts", "on",
    ])
    #expect(options.language == .arabic)
    #expect(options.alertsEnabled == true)
  }

  @Test("the app's clock starts at -now, runs in real time and can jump")
  func clock() {
    let launch = Date(timeIntervalSince1970: 1_000_000)
    let start = Date(timeIntervalSince1970: 2_000_000)
    let clock = AppClock(start: start, launch: launch)
    #expect(clock.now(at: launch.addingTimeInterval(30)) == start.addingTimeInterval(30))
    #expect(clock.real(at: start.addingTimeInterval(30)) == launch.addingTimeInterval(30))
    clock.jump(by: 180)
    #expect(clock.now(at: launch) == start.addingTimeInterval(180))
    #expect(AppClock().now(at: launch) == launch)
  }
}
