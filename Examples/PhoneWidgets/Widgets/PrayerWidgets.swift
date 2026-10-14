import Foundation
import SalahWidgets
import SwiftUI
import WidgetKit

@main
struct PrayerWidgets: WidgetBundle {
  var body: some Widget {
    PrayerWidget()
  }
}

/// The prayer widget, on the Home Screen and the Lock Screen.
struct PrayerWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: PhoneWidgetsID.widgetKind, provider: Provider()) { entry in
      FamilyView(entry: entry)
    }
    .configurationDisplayName(Text(verbatim: "PhoneWidgets"))
    .description(
      Text(verbatim: WidgetStrings(language: .device)("The next prayer and today's times."))
    )
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge,
      .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ])
  }
}

/// Reads the family from WidgetKit and draws the shared view.
private struct FamilyView: View {
  let entry: PrayerEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    PrayerWidgetView(entry: entry, family: family)
  }
}

/// Loads the app's settings from the App Group and builds the timeline in the extension's
/// process, with no help from the app.
nonisolated struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> PrayerEntry {
    Self.sample(at: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
    // The gallery shows Makkah until the app is set up; a placed widget shows its real first
    // entry.
    let settings = SharedValue.widgetSettings.load()
    if context.isPreview && settings == nil {
      completion(Self.sample(at: Date()))
    } else {
      completion(
        PrayerTimelineProvider.timeline(
          settings: settings, now: Date(), deviceLanguage: .device
        ).entries[0])
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
    let timeline = TimelineDiagnostics.timeline(
      settings: SharedValue.widgetSettings.load(), now: Date(), family: "\(context.family)",
      deviceLanguage: .device, log: DiagnosticsLog())
    completion(timeline.widgetKitTimeline)
  }

  /// Makkah's first entry, for the placeholder and the gallery.
  private static func sample(at date: Date) -> PrayerEntry {
    PrayerTimelineProvider.timeline(settings: .defaults, now: date).entries[0]
  }
}
