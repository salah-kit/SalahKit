import Foundation
import SalahCore
import SalahTimes
import SalahWidgets
import SwiftUI
import WidgetKit

/// One state of the widget, made by the extension's provider function.
nonisolated struct WidgetStateSample: Identifiable, Sendable {
  /// `setup`, `normal`, `partial`, `unknownNext`, `unavailable` or `expired`.
  var id: String
  var entry: PrayerEntry

  /// Tromsø at 15:00 on 21 June 2026, between Dhuhr and Asr under the midnight sun: a partial
  /// day (Fajr, sunrise, Maghrib and Isha can't be calculated) with a known next prayer.
  static let midsummerTromso = Date(timeIntervalSince1970: 1_782_046_800)

  /// Makkah at 21:00 on 14 October 2026, after Isha on the last day of a one-day timetable.
  static let afterLastPublishedIsha = Date(timeIntervalSince1970: 1_792_000_800)

  /// Every state, as the extension would show it at `now`, in `language`.
  ///
  /// The normal, unavailable and expired states use `now`; the partial ones are fixed moments.
  /// A calculation knows its next prayer whenever it knows anything, even on Tromsø's partial
  /// days; an unknown next prayer comes from published data that ends, so `unknownNext` uses a
  /// one-day timetable through SalahWidgets' builder. The views handle both.
  static func all(language: NamesLanguage, now: Date) -> [WidgetStateSample] {
    func settings(_ place: Place) -> WidgetSettings {
      WidgetSettings(place: place, method: .ummAlQura, language: language)
    }
    let normal = PrayerTimelineProvider.timeline(settings: settings(.makkah), now: now)
    return [
      WidgetStateSample(
        id: "setup",
        entry: PrayerTimelineProvider.timeline(settings: nil, now: now, deviceLanguage: language)
          .entries[0]),
      WidgetStateSample(id: "normal", entry: normal.entries[0]),
      WidgetStateSample(
        id: "partial",
        entry: PrayerTimelineProvider.timeline(settings: settings(.tromso), now: midsummerTromso)
          .entries[0]),
      WidgetStateSample(id: "unknownNext", entry: unknownNext(language: language)),
      WidgetStateSample(
        id: "unavailable",
        entry: PrayerTimelineProvider.timeline(settings: settings(.invalid), now: now).entries[0]),
      WidgetStateSample(id: "expired", entry: normal.entries[normal.entries.count - 1]),
    ]
  }

  /// After Isha on a timetable's last published day: the day's times are known, the next
  /// prayer isn't.
  private static func unknownNext(language: NamesLanguage) -> PrayerEntry {
    let day = CivilDay(year: 2026, month: 10, day: 14)
    func local(_ hour: Int, _ minute: Int) -> TimetableTime {
      .local(WallClockTime(hour: hour, minute: minute))
    }
    let timetable = TimetableSource(
      rows: [
        TimetableSource.Row(
          day: day,
          times: [
            .fajr: local(5, 0), .sunrise: local(6, 16), .dhuhr: local(12, 7),
            .asr: local(15, 27), .maghrib: local(17, 57), .isha: local(19, 27),
          ])
      ], expectedKinds: Set(PrayerKind.allCases))
    let schedule = PrayerSchedule(source: timetable, location: Place.makkah.location)
    let state =
      (try? PrayerTimelineBuilder(schedule: schedule).timeline(from: afterLastPublishedIsha))?
      .entries.first?.state ?? .expired(knownThrough: afterLastPublishedIsha)
    return PrayerEntry(
      date: afterLastPublishedIsha,
      content: .timeline(
        state,
        EntryContext(language: language, place: .makkah, day: schedule.day(day))))
  }
}

/// Every state of the widget in every family, drawn with the extension's own view code, so a
/// UI test can check the widget's wording in a running app.
struct WidgetStatesView: View {
  let strings: WidgetStrings
  let clock: AppClock

  private static let families: [WidgetFamily] = [
    .systemSmall, .systemMedium, .systemLarge,
    .accessoryCircular, .accessoryRectangular, .accessoryInline,
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ForEach(WidgetStateSample.all(language: strings.language, now: clock.now())) { sample in
          VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title(of: sample.id))
              .font(.title2)
              .fontWeight(.semibold)
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("states.\(sample.id).title")
            ForEach(Self.families, id: \.self) { family in
              WidgetFrame(entry: sample.entry, family: family)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("states.\(sample.id).\(family)")
            }
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("states.\(sample.id)")
        }
      }
      .padding()
    }
    .navigationTitle(Text(verbatim: strings("Widget states")))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func title(of id: String) -> String {
    switch id {
    case "setup": strings("Setup required")
    case "normal": strings("Normal")
    case "partial": strings("Partial")
    case "unknownNext": strings("Partial, next prayer unknown")
    case "unavailable": strings("Unavailable")
    default: strings("Expired")
    }
  }
}

/// A widget entry drawn in the app at its family's size on an iPhone, on the widget's
/// background for the Home Screen families and on a dark one for the Lock Screen's.
struct WidgetFrame: View {
  let entry: PrayerEntry
  let family: WidgetFamily
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let size = Self.size(of: family)
    if family.isAccessory {
      PrayerWidgetView(entry: entry, family: family)
        .padding(family == .accessoryInline ? 4 : 6)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(.white)
        .background(.black.opacity(0.85), in: .rect(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    } else {
      PrayerWidgetView(entry: entry, family: family)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(WidgetPalette.of(colorScheme).surface.color, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.separator))
    }
  }

  /// The family's size on a 6.1-inch iPhone.
  static func size(of family: WidgetFamily) -> CGSize {
    switch family {
    case .systemSmall: CGSize(width: 170, height: 170)
    case .systemMedium: CGSize(width: 364, height: 170)
    case .systemLarge: CGSize(width: 364, height: 382)
    case .accessoryCircular: CGSize(width: 76, height: 76)
    case .accessoryRectangular: CGSize(width: 172, height: 76)
    default: CGSize(width: 260, height: 28)
    }
  }
}
