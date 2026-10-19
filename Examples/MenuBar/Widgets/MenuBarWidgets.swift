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
