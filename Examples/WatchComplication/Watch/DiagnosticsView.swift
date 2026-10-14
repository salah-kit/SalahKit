import SwiftUI
import WidgetKit

/// The complication extension's timeline log, newest first: evidence that the extension ran,
/// with what it read and built. Diagnostics for the example, not part of a prayer app.
struct DiagnosticsView: View {
  let model: WatchModel
  @State private var records: [TimelineRecord] = []

  private var strings: AppStrings { model.strings }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Button {
          WidgetCenter.shared.reloadTimelines(ofKind: WatchStorage.complicationKind)
        } label: {
          Text(verbatim: strings("Reload complication"))
        }
        .accessibilityIdentifier("diagnostics.reload")
        Button {
          records = TimelineLog().records()
        } label: {
          Text(verbatim: strings("Read the log again"))
        }
        .accessibilityIdentifier("diagnostics.refresh")
        Text(verbatim: strings("\(records.count) timelines"))
          .font(.caption2)
          .accessibilityIdentifier("diagnostics.count")
        if records.isEmpty {
          Text(verbatim: strings("The complication hasn't built a timeline yet."))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("diagnostics.empty")
        }
        ForEach(Array(records.reversed().enumerated()), id: \.offset) { index, record in
          Text(verbatim: record.line)
            .font(.system(size: 10, design: .monospaced))
            .accessibilityIdentifier("diagnostics.record.\(index)")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(Text(verbatim: strings("Diagnostics")))
    .onAppear { records = TimelineLog().records() }
  }
}
