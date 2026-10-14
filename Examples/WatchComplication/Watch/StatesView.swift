import SalahCore
import SalahUI
import SwiftUI

/// Every state the complication draws, in every family, with the complication's own views: the
/// current entry from the stored inputs, then fixed samples. UI tests assert them here, in the
/// running app, because a watch face can't be inspected.
struct StatesView: View {
  let model: WatchModel

  private var strings: AppStrings { model.strings }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        current
        ForEach(ComplicationSample.all) { sample in
          SampleRow(
            id: sample.id, title: title(of: sample.id), display: sample.display,
            timeZone: sample.entry.timeZone, placeName: sample.entry.placeName,
            strings: strings, countdown: .staticText)
        }
      }
    }
    .navigationTitle(Text(verbatim: strings("States")))
  }

  /// What the complication shows now, from the stored inputs.
  private var current: some View {
    let now = model.options.date()
    let entry = ComplicationTimeline.entry(
      at: now, in: ComplicationTimeline.make(inputs: model.inputs, now: now).entries)
    return Group {
      if let entry {
        SampleRow(
          id: "now", title: strings("Now, from stored inputs"),
          display: ComplicationDisplay(entry.content, at: entry.date), timeZone: entry.timeZone,
          placeName: entry.placeName, strings: strings,
          countdown: model.options.now == nil ? .live : .staticText)
      }
    }
  }

  private func title(of id: String) -> String {
    switch id {
    case "setup": strings("Missing settings")
    case "next": strings("Next prayer")
    case "partial": strings("Partial schedule")
    case "ended": strings("Timetable ended")
    case "unavailable": strings("Times unavailable")
    case "expired": strings("Timeline expired")
    default: id
    }
  }
}

/// One state in the four families, at about their sizes on a 46 mm watch.
struct SampleRow: View {
  let id: String
  let title: String
  let display: ComplicationDisplay
  let timeZone: TimeZone
  let placeName: String?
  let strings: AppStrings
  let countdown: PrayerCountdown.Mode

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("states.\(id)")
      HStack(spacing: 6) {
        complication(.circular)
          .frame(width: 50, height: 50)
        complication(.corner)
          .frame(width: 50, height: 50)
      }
      complication(.rectangular)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(6)
        .background(.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
      complication(.inline)
        .font(.caption)
        .lineLimit(1)
    }
  }

  private func complication(_ family: ComplicationFamily) -> some View {
    ComplicationView(
      display: display, family: family, timeZone: timeZone, placeName: placeName,
      strings: strings, countdown: countdown, isInApp: true
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("states.\(id).\(family.rawValue)")
  }
}
