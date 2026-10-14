import Foundation
import SalahUI
import SalahWidgets
import SwiftUI
import WidgetKit

/// The complication extension: one widget in four accessory families.
@main
struct ComplicationsBundle: WidgetBundle {
  var body: some Widget {
    PrayerComplication()
  }
}

/// The next prayer and its countdown, from the inputs the watch app stored.
struct PrayerComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchStorage.complicationKind, provider: ComplicationProvider()) {
      entry in
      ComplicationEntryView(entry: entry)
    }
    .configurationDisplayName(Text(verbatim: AppStrings(language: nil)("Next prayer")))
    .description(Text(verbatim: AppStrings(language: nil)("The next prayer and its countdown.")))
    .supportedFamilies(ComplicationFamily.allCases.map(\.widgetFamily))
  }
}

/// The entry in the family WidgetKit asks for.
struct ComplicationEntryView: View {
  let entry: ComplicationEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    ComplicationView(
      display: ComplicationDisplay(entry.content, at: entry.date),
      family: ComplicationFamily(family), timeZone: entry.timeZone,
      placeName: entry.placeName, strings: AppStrings(language: nil)
    )
    .containerBackground(for: .widget) { Color.clear }
  }
}

/// Builds the complication's timelines inside the extension, from the watch's App Group alone:
/// nothing here talks to the iPhone or needs the watch app to be running.
nonisolated struct ComplicationProvider: TimelineProvider {
  func placeholder(in context: Context) -> ComplicationEntry {
    ComplicationSample.placeholder(at: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
    if context.isPreview {
      completion(ComplicationSample.placeholder(at: Date()))
      return
    }
    let entries = ComplicationTimeline.make(inputs: SharedValue.inputs.load(), now: Date()).entries
    completion(entries.first ?? ComplicationSample.placeholder(at: Date()))
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void
  ) {
    let requestedAt = Date()
    let clock = ContinuousClock()
    let start = clock.now
    let inputs = SharedValue.inputs.load()
    let timeline = ComplicationTimeline.make(inputs: inputs, now: requestedAt)
    let elapsed = start.duration(to: clock.now)
    let milliseconds =
      Double(elapsed.components.seconds) * 1_000
      + Double(elapsed.components.attoseconds) / 1e15
    let record = TimelineRecord(
      requestedAt: requestedAt, family: "\(context.family)", inputs: inputs,
      entries: timeline.entries, milliseconds: milliseconds,
      footprintMegabytes: memoryFootprintMegabytes())
    TimelineLog().append(record)
    TimelineLog.logger.notice("\(record.line, privacy: .public)")
    completion(timeline)
  }
}
