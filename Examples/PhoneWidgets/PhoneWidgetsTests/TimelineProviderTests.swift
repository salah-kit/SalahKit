import Foundation
import SalahCore
import SalahWidgets
import Testing

@testable import PhoneWidgets

/// A model of how WidgetKit uses the example's provider, for fixed-clock tests.
///
/// It calls the provider at the start, then at each timeline's reload date plus a chosen delay,
/// or earlier when the app saves settings and asks for a reload; a timeline that never reloads
/// waits for the app. Between calls it shows the latest timeline's last entry whose date has
/// passed. This is the contract WidgetKit documents, not its actual scheduling.
struct ProviderHost {
  struct Call {
    var date: Date
    var settings: WidgetSettings?
    var timeline: WidgetTimeline
  }

  private(set) var calls: [Call] = []

  /// Runs the provider from `start` until `end`.
  ///
  /// - Parameters:
  ///   - delays: Extra seconds after a timeline's reload date, by the index of the call that made
  ///     the timeline.
  ///   - appReloads: Dates at which the app saves changed settings and asks for a reload.
  ///   - settings: The settings in the App Group at a date.
  init(
    from start: Date, until end: Date, delays: [Int: TimeInterval] = [:],
    appReloads: [Date] = [], settings: (Date) -> WidgetSettings?
  ) {
    var date = start
    while date < end {
      let stored = settings(date)
      let timeline = PrayerTimelineProvider.timeline(settings: stored, now: date)
      calls.append(Call(date: date, settings: stored, timeline: timeline))
      var next: Date
      switch timeline.reload {
      case .never: next = .distantFuture
      case .after(let reload): next = reload.addingTimeInterval(delays[calls.count - 1] ?? 0)
      }
      if let reload = appReloads.filter({ $0 > date && $0 < next }).min() {
        next = reload
      }
      guard next > date else {
        Issue.record("the next call, \(next), isn't after the call at \(date)")
        break
      }
      date = next
    }
  }

  /// The entry showing at `date`, and the call that supplied it.
  func displayed(at date: Date) -> (call: Call, entry: PrayerEntry)? {
    guard let call = calls.last(where: { $0.date <= date }),
      let entry = call.timeline.entries.last(where: { $0.date <= date })
    else { return nil }
    return (call, entry)
  }
}

/// The parts of a schedule state a widget shows, without the moment and the coverage's interval.
struct ShownState: Hashable, CustomStringConvertible {
  var isAvailable: Bool
  var latestPrayer: String?
  var next: String?
  var nextPrayer: String?
  var justStarted: String?
  var isApproaching: Bool

  init(_ state: ScheduleState) {
    let prayer = state.prayerState
    isAvailable = prayer != nil
    latestPrayer = prayer?.latestPrayer?.id
    next = prayer?.next?.id
    nextPrayer = prayer?.nextPrayer?.id
    justStarted = prayer?.justStarted?.id
    isApproaching = prayer?.isApproaching ?? false
  }

  var description: String {
    "available: \(isAvailable), next prayer: \(nextPrayer ?? "nil"), latest: \(latestPrayer ?? "nil")"
  }
}

/// Successive 48-hour timelines of the example's own provider over seven days, with a fixed
/// clock and a calculated source.
@Suite("The widget's timelines over seven days")
struct TimelineProviderTests {
  /// 2026-10-13 12:00 in Makkah.
  static let start = Date(timeIntervalSince1970: 1_791_882_000)
  static let week: TimeInterval = 7 * 86_400
  static let makkah = WidgetSettings(place: .makkah, method: .ummAlQura, language: .english)

  @Test("a calculated widget shows every prayer in turn, with a reload a day")
  func onTime() throws {
    let host = ProviderHost(from: Self.start, until: Self.start + Self.week) { _ in Self.makkah }
    let shown = check(host, from: Self.start, through: Self.start + Self.week)

    #expect(shown.expired.isEmpty)
    #expect(host.calls.count == 7)
    for call in host.calls {
      let planned = try #require(call.timeline.prayerTimeline)
      #expect(planned.horizon.duration == 48 * 3_600)
      #expect(planned.isTruncated == false)
      #expect(call.timeline.reload == .after(call.date.addingTimeInterval(24 * 3_600)))
      // The last entry is the timeline-expired one, at the end of the validity.
      #expect(call.timeline.entries.last?.date == planned.validUntil)
      guard case .timeline(.expired(let through), _)? = call.timeline.entries.last?.content else {
        Issue.record("the last entry isn't the expired one")
        continue
      }
      #expect(through == planned.validUntil)
    }
    // Every prayer of the week becomes the next prayer, in order.
    let schedule = Self.makkah.schedule
    let prayers = schedule.events(from: Self.start, through: Self.start + Self.week + 86_400)
      .events.filter { $0.kind.isPrayer && $0.time > Self.start }.map(\.id)
    #expect(shown.nextPrayers == Array(prayers.prefix(shown.nextPrayers.count)))
    #expect(shown.nextPrayers.count >= 35)
    // The listed day turned over at each of the seven midnights, at midnight.
    #expect(shown.days.count == 8)
    #expect(shown.days.first == CivilDay(year: 2026, month: 10, day: 13))
  }

  @Test("a provider call later than the validity shows the expired entry until it comes")
  func delayedCall() throws {
    // Call 2's timeline asks for a reload after 24 hours and is valid for 48; the next call
    // comes 30 hours after the reload date, 6 hours past the validity.
    let host = ProviderHost(
      from: Self.start, until: Self.start + Self.week, delays: [2: 30 * 3_600]
    ) { _ in Self.makkah }
    try #require(host.calls.count >= 4)
    let late = try #require(host.calls[2].timeline.prayerTimeline?.validUntil)
    let shown = check(host, from: Self.start, through: Self.start + Self.week)

    #expect(host.calls[3].date == late.addingTimeInterval(6 * 3_600))
    #expect(shown.expired.contains(late))
    #expect(shown.expired.contains(host.calls[3].date.addingTimeInterval(-1)))
    #expect(shown.expired.allSatisfy { $0 >= late && $0 < host.calls[3].date })
    // The expired entry shows no times: its display is the expired one.
    let entry = try #require(host.displayed(at: late.addingTimeInterval(3_600))?.entry)
    #expect(WidgetDisplay(entry.content) == .expired(knownThrough: late))
  }

  @Test("a call late by less than the slack never shows the expired entry")
  func delayWithinSlack() {
    let host = ProviderHost(
      from: Self.start, until: Self.start + Self.week, delays: [1: 20 * 3_600, 4: 23 * 3_600]
    ) { _ in Self.makkah }
    #expect(check(host, from: Self.start, through: Self.start + Self.week).expired.isEmpty)
  }

  @Test("no settings at first: setup required until the app saves them and asks for a reload")
  func initialMissingSettings() throws {
    let saved = Self.start.addingTimeInterval(5 * 3_600)
    let host = ProviderHost(
      from: Self.start, until: Self.start + 3 * 86_400, appReloads: [saved]
    ) { date in date < saved ? nil : Self.makkah }

    try #require(host.calls.count >= 2)
    // The setup prompt never asks for a reload, so the next call is the app's.
    #expect(host.calls[0].timeline.reload == .never)
    #expect(host.calls[0].timeline.entries.count == 1)
    #expect(host.calls.map(\.date).prefix(2) == [Self.start, saved])
    for minutes in stride(from: 0, to: 300, by: 15) {
      let entry = host.displayed(at: Self.start.addingTimeInterval(TimeInterval(minutes * 60)))
      #expect(entry.map { WidgetDisplay($0.entry.content) } == .setupRequired)
    }
    let shown = check(host, from: saved, through: Self.start + 3 * 86_400)
    #expect(shown.expired.isEmpty)
    // 17:00 in Makkah: Asr (15:27) has passed, Maghrib is next.
    let after = try #require(host.displayed(at: saved)?.entry)
    guard case .times(let times) = WidgetDisplay(after.content) else {
      Issue.record("after the save: \(after.content)")
      return
    }
    #expect(times.state.latestPrayer?.kind == .asr)
    #expect(times.state.nextPrayer?.kind == .maghrib)
  }

  @Test("Tromsø at midsummer: a partial day with a known next prayer, unavailable after Asr")
  func partialDays() throws {
    let tromso = WidgetSettings(place: .tromso, method: .ummAlQura, language: .english)
    // 2026-06-15 12:00 UTC.
    let june = Date(timeIntervalSince1970: 1_781_524_800)
    let host = ProviderHost(from: june, until: june + Self.week) { _ in tromso }
    let shown = check(host, from: june, through: june + Self.week)

    #expect(shown.expired.isEmpty)
    #expect(shown.partial > 0)
    // 15:00 on 21 June, between Dhuhr and Asr: a partial day with a known next prayer.
    let afternoon = try #require(host.displayed(at: WidgetStateSample.midsummerTromso)?.entry)
    guard case .times(let times) = WidgetDisplay(afternoon.content) else {
      Issue.record("Tromsø at 15:00 on 21 June: \(afternoon.content)")
      return
    }
    #expect(times.isPartial)
    #expect(times.nextIsUnknown == false)
    #expect(times.state.latestPrayer?.kind == .dhuhr)
    #expect(times.state.nextPrayer?.kind == .asr)
    #expect(times.missingKinds == [.fajr, .sunrise, .maghrib, .isha])
    #expect(times.missingReason == .cannotCalculate)
    #expect(times.day?.events.map(\.kind) == [.dhuhr, .asr])
    // 20:00, after Asr: Maghrib may fall anywhere until the next Dhuhr, so nothing can be
    // asserted, and the widget says the times can't be calculated.
    let evening = try #require(
      host.displayed(at: WidgetStateSample.midsummerTromso.addingTimeInterval(5 * 3_600))?.entry)
    #expect(WidgetDisplay(evening.content) == .unavailable(.cannotCalculate))
  }

  @Test("invalid coordinates: every entry before the expired one is unavailable")
  func invalidPlace() throws {
    let invalid = WidgetSettings(place: .invalid, method: .ummAlQura, language: .english)
    let timeline = PrayerTimelineProvider.timeline(settings: invalid, now: Self.start)
    let displays = timeline.entries.map { WidgetDisplay($0.content) }
    #expect(displays.dropLast().allSatisfy { $0 == .unavailable(.invalidInput) })
    #expect(
      displays.last == .expired(knownThrough: try #require(timeline.prayerTimeline?.validUntil)))
  }

  @Test("the builder's midnight entries evaluate the exact state and list the new day")
  func midnightEntries() throws {
    let timeline = PrayerTimelineProvider.timeline(settings: Self.makkah, now: Self.start)
    let planned = try #require(timeline.prayerTimeline)
    let zone = Place.makkah.location.timeZone
    let lookahead = CivilDay(containing: planned.horizon.end, in: zone).adding(days: 2)
      .start(in: zone)
    let midnights = (1...2).map {
      CivilDay(containing: Self.start, in: zone).adding(days: $0).start(in: zone)
    }
    for midnight in midnights {
      let index = try #require(timeline.entries.firstIndex { $0.date == midnight })
      guard case .timeline(let state, let context) = timeline.entries[index].content,
        case .timeline(let before, _) = timeline.entries[index - 1].content
      else {
        Issue.record("no timeline entries around \(midnight)")
        continue
      }
      #expect(state == .schedule(Self.makkah.schedule.state(at: midnight, through: lookahead)))
      #expect(state.prayerState?.date == midnight)
      // Only the listed day changes; the prayer facts still agree with the preceding entry.
      if case .schedule(let exact) = state, case .schedule(let earlier) = before {
        #expect(ShownState(exact) == ShownState(earlier))
      }
      #expect(context.day.day?.day == CivilDay(containing: midnight, in: zone))
    }
    #expect(timeline.entries.map(\.date) == timeline.entries.map(\.date).sorted())
    #expect(timeline.entries.map(\.date) == planned.entries.map(\.date))
  }

  @Test("the real provider maps the bounded builder timeline without adding entries")
  func boundedConstruction() throws {
    // A long horizon fills the builder's budget; provider-added midnights used to exceed it.
    let horizon = Duration.seconds(14 * 86_400)
    let timeline = PrayerTimelineProvider.timeline(
      settings: Self.makkah, now: Self.start, horizon: horizon)
    let expected = try PrayerTimelineBuilder(
      schedule: Self.makkah.schedule, includeDayBoundaries: true
    ).timeline(from: Self.start, horizon: horizon)
    #expect(timeline.prayerTimeline == expected)
    #expect(timeline.entries.count == 96)
    #expect(expected.isTruncated)
    #expect(timeline.entries.map(\.date) == expected.entries.map(\.date))
    for (entry, planned) in zip(timeline.entries, expected.entries) {
      guard case .timeline(let state, let context) = entry.content else {
        Issue.record("settings produced a setup entry")
        continue
      }
      #expect(state == planned.state)
      #expect(context.day == Self.makkah.schedule.day(containing: entry.date))
    }
  }

  @Test("the real provider turns over London's list through a 23-hour day")
  func dstConstruction() throws {
    let settings = WidgetSettings(place: .london, method: .muslimWorldLeague, language: .english)
    let zone = settings.place.location.timeZone
    let day = CivilDay(year: 2026, month: 3, day: 28)
    let start = day.start(in: zone).addingTimeInterval(12 * 3_600)
    let timeline = PrayerTimelineProvider.timeline(
      settings: settings, now: start, horizon: .seconds(3 * 86_400))
    let first = day.adding(days: 1).start(in: zone)
    let second = day.adding(days: 2).start(in: zone)
    #expect(second.timeIntervalSince(first) == 23 * 3_600)
    for midnight in [first, second] {
      let entry = try #require(timeline.entries.first { $0.date == midnight })
      guard case .timeline(.schedule(let state), let context) = entry.content else {
        Issue.record("a midnight lacks a schedule entry")
        continue
      }
      #expect(state.prayerState?.date == midnight)
      #expect(context.day.day?.day == CivilDay(containing: midnight, in: zone))
    }
  }

  // MARK: Checking what a host shows

  struct Shown {
    var expired: [Date] = []
    var nextPrayers: [String] = []
    /// The days the entries on show listed at the first sample of each civil day, in order,
    /// without repeats.
    var days: [CivilDay] = []
    var partial = 0
  }

  /// Checks the host every five minutes and one second either side of every entry and event:
  /// a schedule entry shows what the schedule says at that instant and lists the instant's own
  /// day, never after its timeline's validity; an expired entry shows only after it.
  func check(_ host: ProviderHost, from start: Date, through end: Date) -> Shown {
    var samples = Set(stride(from: start, through: end, by: 300))
    for call in host.calls {
      for entry in call.timeline.entries {
        samples.formUnion([entry.date, entry.date - 1, entry.date + 1])
      }
      if let settings = call.settings {
        for event in settings.schedule.events(from: start, through: end).events {
          samples.formUnion([event.time - 1, event.time, event.time + 1])
        }
      }
    }
    var shown = Shown()
    var sampleDay: CivilDay?
    for date in samples.sorted() where date >= start && date <= end {
      guard let (call, entry) = host.displayed(at: date) else {
        Issue.record("nothing shown at \(date)")
        continue
      }
      guard let settings = call.settings, let planned = call.timeline.prayerTimeline else {
        continue
      }
      let zone = settings.place.location.timeZone
      guard case .timeline(let state, let context) = entry.content else {
        Issue.record("setup required at \(date) with settings")
        continue
      }
      switch state {
      case .schedule(let scheduleState):
        if date >= planned.validUntil {
          Issue.record("a schedule state at \(date), after the validity \(planned.validUntil)")
        }
        let lookahead = CivilDay(containing: planned.horizon.end, in: zone).adding(days: 2)
          .start(in: zone)
        let expected = settings.schedule.state(at: date, through: lookahead)
        if ShownState(scheduleState) != ShownState(expected) {
          Issue.record("at \(date): \(ShownState(scheduleState)), expected \(ShownState(expected))")
        }
        let day = CivilDay(containing: date, in: zone)
        if context.day.day.map(\.day) != day && context.day != settings.schedule.day(day) {
          Issue.record("at \(date): lists \(context.day), expected \(day)")
        }
        // The day the entry on show lists, at the first sample of each civil day: without an
        // entry at midnight it would still be the day before.
        if day != sampleDay {
          sampleDay = day
          if let listed = context.day.day?.day, shown.days.last != listed {
            shown.days.append(listed)
          }
        }
        if let next = scheduleState.prayerState?.nextPrayer?.id, shown.nextPrayers.last != next {
          shown.nextPrayers.append(next)
        }
        if case .times(let times) = WidgetDisplay(entry.content), times.isPartial {
          shown.partial += 1
        }
      case .expired(let knownThrough):
        if knownThrough != planned.validUntil || date < knownThrough {
          Issue.record("expired through \(knownThrough) shown at \(date)")
        }
        shown.expired.append(date)
      }
    }
    return shown
  }
}
