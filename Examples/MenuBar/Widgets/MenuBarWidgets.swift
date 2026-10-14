import AppIntents
import SalahCore
import SalahUI
import SalahWidgets
import SwiftUI
import WidgetKit

@main
struct MenuBarWidgets: WidgetBundle {
  var body: some Widget {
    PrayerWidget()
  }
}

/// The prayer widget, on the desktop and in Notification Center, with a Stop button while the
/// app plays its tone.
struct PrayerWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: MenuBarID.widgetKind, provider: Provider()) { entry in
      PrayerWidgetView(entry: entry)
        .containerBackground(.background, for: .widget)
    }
    .configurationDisplayName(Text(verbatim: "MenuBar"))
    .description(Text("The next prayer, with a button that stops MenuBar's tone."))
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

/// Loads the app's settings and what plays from the App Group, and builds the timeline in the
/// extension's process.
nonisolated struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> MenuBarEntry {
    MenuBarTimeline.timeline(settings: .defaults, nowPlaying: nil, now: Date()).entries[0]
  }

  func getSnapshot(in context: Context, completion: @escaping (MenuBarEntry) -> Void) {
    // The gallery shows Makkah until the app has run; a placed widget shows its first entry.
    let settings = SharedValue.menuBarSettings.load()
    let entries = MenuBarTimeline.timeline(
      settings: context.isPreview ? settings ?? .defaults : settings,
      nowPlaying: SharedValue.nowPlaying.load(), now: Date()
    ).entries
    completion(entries[0])
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MenuBarEntry>) -> Void) {
    let (entries, reloadDate) = MenuBarTimeline.timeline(
      settings: SharedValue.menuBarSettings.load(), nowPlaying: SharedValue.nowPlaying.load(),
      now: Date())
    completion(Timeline(entries: entries, policy: reloadDate.map { .after($0) } ?? .never))
  }
}

/// One entry, in the small or medium family.
struct PrayerWidgetView: View {
  let entry: MenuBarEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let language: NamesLanguage =
      if case .timeline(_, let context) = entry.content { context.language } else { .english }
    let strings = MenuBarStrings(language: language)
    VStack(alignment: .leading, spacing: 6) {
      content(strings)
      Spacer(minLength: 0)
      if let playing = entry.nowPlaying {
        StopButton(nowPlaying: playing, strings: strings)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .environment(\.locale, strings.locale)
    .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
  }

  @ViewBuilder
  private func content(_ strings: MenuBarStrings) -> some View {
    switch entry.content {
    case .setupRequired:
      Text(verbatim: strings("Open MenuBar to set up prayer times."))
        .font(.callout)
    case .timeline(let state, let context):
      let zone = context.place.location.timeZone
      switch state {
      case .schedule(.available(let prayer, _)):
        HStack(alignment: .top, spacing: 12) {
          NextPrayerView(
            state: prayer, names: strings.names, timeZone: zone, countdown: .staticText)
          if family == .systemMedium, let day = context.day.day {
            PrayerTimesList(day: day, state: prayer, names: strings.names, countdown: .staticText)
              .font(.caption)
          }
        }
      case .schedule(.unavailable(let coverage, _)):
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: strings("No prayer times are known now"))
            .font(.callout)
          if let reason = coverage.gaps.first?.reason {
            Text(verbatim: strings.reason(reason))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      case .expired(let knownThrough):
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: strings("Open MenuBar to update."))
            .font(.callout)
          Text(
            verbatim: strings("Times shown until \(strings.dayAndTime(knownThrough, in: zone)).")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
    }
  }
}

/// The Stop button: it runs ``StopPlaybackIntent`` in the extension's process.
private struct StopButton: View {
  let nowPlaying: NowPlaying
  let strings: MenuBarStrings

  var body: some View {
    Button(intent: StopPlaybackIntent()) {
      Label {
        Text(verbatim: strings("Stop"))
      } icon: {
        Image(systemName: "stop.fill")
      }
    }
    .accessibilityLabel(Text(verbatim: label))
  }

  private var label: String {
    guard let alert = nowPlaying.alert else { return strings("Stop the tone") }
    return strings("Stop the tone for \(strings.names.name(of: alert.prayer))")
  }
}
