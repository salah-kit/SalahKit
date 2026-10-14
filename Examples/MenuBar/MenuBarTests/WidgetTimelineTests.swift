import Foundation
import SalahCore
import SalahWidgets
import Testing

@testable import MenuBar

/// The widget's timeline logic, which the extension, these tests and the stop harness run, and
/// the stop intent's work.
@Suite("Widget timeline")
@MainActor
struct WidgetTimelineTests {
  @Test("without settings, one setup entry and no reload")
  func setupRequired() {
    let (entries, reload) = MenuBarTimeline.timeline(settings: nil, nowPlaying: nil, now: Date())
    #expect(entries.count == 1)
    #expect(entries[0].content == .setupRequired)
    #expect(reload == nil)
  }

  @Test("a steps timeline: a minute grid near prayers, the expired entry last, midnights added")
  func stepsTimeline() throws {
    let asr = try Fixture.event(.asr)
    let now = asr.time.addingTimeInterval(-45 * 60)
    let (entries, reload) = MenuBarTimeline.timeline(
      settings: Fixture.makkah, nowPlaying: nil, now: now)
    let dates = entries.map(\.date)
    #expect(dates == dates.sorted())
    #expect(entries.first?.date == now)
    guard case .timeline(.expired(let knownThrough), _) = entries.last?.content else {
      Issue.record("the last entry isn't the expired one")
      return
    }
    #expect(knownThrough > now)
    #expect(reload.map { $0 > now && $0 < knownThrough } == true)
    // Within 30 minutes of Asr, an entry every minute.
    let near = dates.filter { abs($0.timeIntervalSince(asr.time)) <= 30 * 60 }
    #expect(near.count == 61)
    // The day turns over at midnight in Makkah, though no state changes there.
    let midnight = Fixture.day.adding(days: 1).start(in: Place.makkah.location.timeZone)
    if knownThrough > midnight {
      let entry = try #require(entries.first { $0.date == midnight })
      guard case .timeline(_, let context) = entry.content else {
        Issue.record("the midnight entry has no timeline state")
        return
      }
      #expect(context.day.day?.day == Fixture.day.adding(days: 1))
    }
  }

  @Test("every entry shows the Stop button while a tone plays")
  func stopButton() {
    let playing = NowPlaying(alert: nil, startedAt: Date())
    let withTone = MenuBarTimeline.timeline(
      settings: Fixture.makkah, nowPlaying: playing, now: Date()
    ).entries
    #expect(withTone.allSatisfy { $0.showsStopButton })
    let without = MenuBarTimeline.timeline(settings: Fixture.makkah, nowPlaying: nil, now: Date())
      .entries
    #expect(without.allSatisfy { !$0.showsStopButton })
    let setup = MenuBarTimeline.timeline(settings: nil, nowPlaying: playing, now: Date()).entries
    #expect(setup[0].showsStopButton)
  }

  @Test("the intent's work clears the stored value, reloads the widget and posts the signal")
  func stopRequest() async throws {
    let recorder = ReloadRecorder()
    let storage = TestStorage.nowPlaying(recorder)
    let signal = TestStorage.signal()
    try storage.save(NowPlaying(alert: nil, startedAt: Date()))
    let received = Counter()
    let observation = signal.observe { received.count += 1 }
    #expect(StopRequest.send(nowPlaying: storage, signal: signal))
    #expect(storage.load() == nil)
    #expect(recorder.reloads == [[MenuBarID.widgetKind]])
    #expect(await eventually { received.count == 1 })
    observation.cancel()
  }
}

extension WidgetTimelineTests {
  @Test("an evening timeline has an entry at midnight for the next day's list")
  func midnightEntry() throws {
    let isha = try Fixture.event(.isha)
    let now = isha.time.addingTimeInterval(31 * 60)
    let (entries, _) = MenuBarTimeline.timeline(settings: Fixture.makkah, nowPlaying: nil, now: now)
    let midnight = Fixture.day.adding(days: 1).start(in: Place.makkah.location.timeZone)
    let entry = try #require(entries.first { $0.date == midnight })
    guard case .timeline(.schedule, let context) = entry.content else {
      Issue.record("the midnight entry has no schedule state")
      return
    }
    #expect(context.day.day?.day == Fixture.day.adding(days: 1))
    let before = try #require(entries.last { $0.date < midnight })
    guard case .timeline(_, let earlier) = before.content else { return }
    #expect(earlier.day.day?.day == Fixture.day)
  }
}
