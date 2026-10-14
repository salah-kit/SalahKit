import Foundation
import SalahCalculation
import SalahCore
import SalahWidgets
import Testing
import WidgetKit

@testable import WatchComplicationWatch

/// The complication's timeline with a fixed clock: what the extension gives WidgetKit for
/// missing inputs, a calculated source and a timetable that ends.
struct TimelineTests {
  /// 14:00 in Makkah on Wednesday 14 October 2026.
  static let makkahAfternoon = date("2026-10-14T14:00:00+03:00")
  /// The sample mosque's timetable with rows for 14 to 16 October 2026.
  static let mosque = ComplicationSample.mosque
  static let london = InputsPreset.mosqueLocation.timeZone

  static func date(_ text: String) -> Date {
    (try? Date(text, strategy: .iso8601)) ?? .distantPast
  }

  private func displays(_ timeline: Timeline<ComplicationEntry>) -> [ComplicationDisplay] {
    timeline.entries.map { ComplicationDisplay($0.content, at: $0.date) }
  }

  // MARK: Missing inputs

  @Test func missingInputsGiveOneSetupEntryThatWaitsForTheApp() {
    let timeline = ComplicationTimeline.make(inputs: nil, now: Self.makkahAfternoon)
    #expect(timeline.entries.count == 1)
    #expect(timeline.entries.first?.date == Self.makkahAfternoon)
    #expect(timeline.entries.first?.content == .setupRequired)
    #expect(displays(timeline) == [.setupRequired])
    // The watch app reloads the complication when inputs arrive; nothing else would help.
    #expect(timeline.policy == .never)
  }

  // MARK: Calculated source

  @Test func aCalculatedSourceGivesNextPrayersThenTheTimelineExpiredEntry() throws {
    let now = Self.makkahAfternoon
    let timeline = ComplicationTimeline.make(inputs: ComplicationSample.makkah, now: now)
    let entries = timeline.entries
    let end = now.addingTimeInterval(48 * 3_600)

    #expect(entries.first?.date == now)
    #expect(entries.map(\.date) == entries.map(\.date).sorted())
    // Every entry before the last knows the next prayer: a calculation never runs out.
    for entry in entries.dropLast() {
      guard case .next = ComplicationDisplay(entry.content, at: entry.date) else {
        Issue.record("Entry at \(entry.date) isn't a next-prayer entry: \(entry.content)")
        continue
      }
    }
    // The last entry is the timeline's end, worded as "needs refreshing", never as a gap in
    // the source.
    let last = try #require(entries.last)
    #expect(last.date == end)
    #expect(last.content == .timeline(.expired(knownThrough: end)))
    #expect(ComplicationDisplay(last.content, at: last.date) == .timelineExpired(knownThrough: end))
    // WidgetKit is asked for the next timeline halfway, after 24 hours.
    #expect(timeline.policy == .after(now.addingTimeInterval(24 * 3_600)))
    // At 14:00 in Makkah, Asr is next.
    let first = try #require(entries.first)
    guard case .next(let state) = ComplicationDisplay(first.content, at: first.date) else {
      Issue.record("The first entry isn't a next-prayer entry")
      return
    }
    #expect(state.nextPrayer?.kind == .asr)
    #expect(first.timeZone.identifier == "Asia/Riyadh")
    #expect(first.placeName == "Makkah")
  }

  @Test func theTimelineMatchesSalahWidgetsOwnWidgetKitTimeline() {
    let now = Self.makkahAfternoon
    let inputs = ComplicationSample.makkah
    let ours = ComplicationTimeline.make(inputs: inputs, now: now)
    let builder = PrayerTimelineBuilder(schedule: inputs.schedule)
    let plain = try? builder.timeline(from: now)
    #expect(ours.entries.map(\.date) == plain?.entries.map(\.date))
    #expect(ours.entries.map(\.content) == plain?.entries.map { .timeline($0.state) })
    #expect(plain.map { ours.policy == .after($0.reloadDate) } == true)
  }

  // MARK: Timetable that ends

  @Test func aTimetableThatEndsShowsTheEndedViewNotTheTimelineExpiredView() throws {
    // Noon on the timetable's last day, 16 October, in London.
    let now = Self.date("2026-10-16T12:00:00+01:00")
    let timeline = ComplicationTimeline.make(inputs: Self.mosque, now: now)
    let entries = timeline.entries
    let midnight = CivilDay(year: 2026, month: 10, day: 17).start(in: Self.london)

    // Before midnight, the last row's prayers are known.
    let beforeMidnight = entries.filter { $0.date < midnight && $0 != entries.last }
    #expect(!beforeMidnight.isEmpty)
    // From midnight, the source has no published data: a source gap that only new data from
    // the iPhone fixes.
    let ended = try #require(entries.first { $0.date == midnight })
    guard case .timeline(.schedule(.unavailable(let coverage, _))) = ended.content else {
      Issue.record("The entry at midnight isn't an unavailable schedule state: \(ended.content)")
      return
    }
    #expect(coverage.gaps.first?.reason == .noPublishedData)
    #expect(
      ComplicationDisplay(ended.content, at: ended.date)
        == .timetableEnded(day: CivilDay(year: 2026, month: 10, day: 17)))
    #expect(ended.lastPublishedDay == CivilDay(year: 2026, month: 10, day: 16))

    // No source gap is ever worded as the timeline's end, and the timeline's end is never
    // worded as a source gap.
    for entry in entries {
      let display = ComplicationDisplay(entry.content, at: entry.date)
      switch entry.content {
      case .timeline(.expired):
        #expect(entry == entries.last)
        guard case .timelineExpired = display else {
          Issue.record("The expired entry shows \(display)")
          continue
        }
      case .timeline(.schedule):
        if case .timelineExpired = display {
          Issue.record("A schedule entry at \(entry.date) shows the timeline-expired view")
        }
      case .setupRequired:
        Issue.record("A timeline with inputs has a setup entry")
      }
    }
    let last = try #require(entries.last)
    #expect(
      ComplicationDisplay(last.content, at: last.date)
        == .timelineExpired(knownThrough: now.addingTimeInterval(48 * 3_600)))
  }

  @Test func afterTheLastIshaTheLatestPrayerStaysKnownAndTheNextIsUnknown() throws {
    let lateEvening = Self.date("2026-10-16T22:30:00+01:00")
    let entries = ComplicationTimeline.make(inputs: Self.mosque, now: lateEvening).entries
    let first = try #require(entries.first)
    guard case .partial(let state, let reason) = ComplicationDisplay(first.content, at: first.date)
    else {
      Issue.record("Late on the last day isn't a partial state: \(first.content)")
      return
    }
    #expect(state.latestPrayer?.kind == .isha)
    #expect(state.nextPrayer == nil)
    #expect(reason == .noPublishedData)
  }

  @Test func aTimetableAlreadyEndedStartsWithTheEndedView() throws {
    let now = Self.date("2026-10-18T09:00:00+01:00")
    let timeline = ComplicationTimeline.make(inputs: Self.mosque, now: now)
    let displays = displays(timeline)
    // The gap that holds the moment is the one of the first day without a row.
    #expect(displays.first == .timetableEnded(day: CivilDay(year: 2026, month: 10, day: 17)))
    #expect(
      displays.dropLast().allSatisfy {
        if case .timetableEnded = $0 { return true }
        return false
      })
    #expect(displays.last == .timelineExpired(knownThrough: now.addingTimeInterval(48 * 3_600)))
  }

  // MARK: Displays

  @Test func otherSourceGapsAreUnavailableWithTheirReason() throws {
    let now = Self.makkahAfternoon
    let entries = ComplicationTimeline.make(inputs: ComplicationSample.invalidPlace, now: now)
      .entries
    let first = try #require(entries.first)
    #expect(ComplicationDisplay(first.content, at: first.date) == .unavailable(.invalidData))
  }

  @Test func thePlaceholderCountsDownFromTheMomentItsAskedFor() throws {
    for now in [Self.makkahAfternoon, Self.makkahAfternoon.addingTimeInterval(400 * 86_400)] {
      let placeholder = ComplicationSample.placeholder(at: now)
      #expect(placeholder.date <= now)
      guard case .next(let state) = ComplicationDisplay(placeholder.content, at: now) else {
        Issue.record("The placeholder at \(now) isn't a next-prayer entry")
        continue
      }
      let next = try #require(state.nextPrayer)
      #expect(next.time > now)
      #expect(next.time.timeIntervalSince(now) < 86_400)
    }
  }

  @Test func theStatesScreenSamplesShowEachState() {
    let byID = Dictionary(uniqueKeysWithValues: ComplicationSample.all.map { ($0.id, $0) })
    #expect(
      ComplicationSample.all.map(\.id) == [
        "setup", "next", "partial", "ended", "unavailable", "expired",
      ])
    #expect(byID["setup"]?.display == .setupRequired)
    #expect(byID["next"].map { if case .next = $0.display { true } else { false } } == true)
    #expect(
      byID["partial"].map {
        if case .partial(_, .noPublishedData) = $0.display { true } else { false }
      } == true)
    #expect(
      byID["ended"]?.display == .timetableEnded(day: CivilDay(year: 2026, month: 10, day: 17)))
    #expect(byID["unavailable"]?.display == .unavailable(.invalidData))
    #expect(
      byID["expired"]?.display
        == .timelineExpired(knownThrough: Self.makkahAfternoon.addingTimeInterval(48 * 3_600)))
  }

  // MARK: Diagnostics

  @Test func aTimelineRecordSummarizesTheTimeline() {
    let now = Self.date("2026-10-16T12:00:00+01:00")
    let entries = ComplicationTimeline.make(inputs: Self.mosque, now: now).entries
    let record = TimelineRecord(
      requestedAt: now, family: "accessoryRectangular", inputs: Self.mosque, entries: entries,
      milliseconds: 1.5, footprintMegabytes: 4)
    #expect(record.inputs == Self.mosque.fingerprint)
    #expect(record.entryCount == entries.count)
    #expect(record.firstEntry == now)
    #expect(record.validUntil == now.addingTimeInterval(48 * 3_600))
    #expect(record.states.hasPrefix("next×"))
    #expect(record.states.contains("partial×"))
    #expect(record.states.contains("timetableEnded×"))
    #expect(record.states.hasSuffix("timelineExpired×1"))
    #expect(record.line.contains("inputs=\(Self.mosque.fingerprint)"))

    let none = TimelineRecord(
      requestedAt: now, family: "accessoryCircular", inputs: nil,
      entries: ComplicationTimeline.make(inputs: nil, now: now).entries, milliseconds: 0.1,
      footprintMegabytes: nil)
    #expect(none.inputs == "none")
    #expect(none.states == "setup×1")
    #expect(none.validUntil == nil)
  }

  @Test func theTimelineLogKeepsTheLatestRecords() {
    let suite = "test.\(UUID().uuidString)"
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let log = TimelineLog(store: SharedValue(appGroup: suite, key: "timelineLog.v1"))
    let now = Self.makkahAfternoon
    for index in 0..<(TimelineLog.limit + 5) {
      log.append(
        TimelineRecord(
          requestedAt: now.addingTimeInterval(Double(index)), family: "f", inputs: nil,
          entries: [], milliseconds: 0, footprintMegabytes: nil))
    }
    let records = log.records()
    #expect(records.count == TimelineLog.limit)
    #expect(records.first?.requestedAt == now.addingTimeInterval(5))
    #expect(records.last?.requestedAt == now.addingTimeInterval(Double(TimelineLog.limit + 4)))
  }

  @Test func theMemoryFootprintIsMeasured() {
    let footprint = memoryFootprintMegabytes()
    #expect(footprint.map { $0 > 0 } == true)
  }
}
