import Foundation
import SwiftUI

/// The extension's diagnostics log, newest first, read from the App Group every two seconds.
///
/// The latest record is shown in full; the seven-day soak and the UI tests read it here.
struct WidgetLogView: View {
  let strings: WidgetStrings
  @State private var records: [DiagnosticsRecord] = []

  var body: some View {
    List {
      Section {
        Text(verbatim: strings("Records: \(records.count.formatted())"))
          .accessibilityIdentifier("log.count")
        Text(verbatim: "#\(records.last?.sequence ?? 0)")
          .font(.footnote.monospaced())
          .accessibilityLabel(Text(verbatim: "\(records.last?.sequence ?? 0)"))
          .accessibilityIdentifier("log.latestSequence")
        Button {
          reload()
        } label: {
          Text(verbatim: strings("Refresh"))
        }
        .accessibilityIdentifier("log.refresh")
      } footer: {
        Text(
          verbatim: strings(
            "The extension appends a record on every timeline it builds and keeps the last 200. Diagnostics only: a widget doesn't need this."
          ))
      }
      if let latest = records.last {
        Section {
          RecordDetail(record: latest, prefix: "log.latest")
        } header: {
          Text(verbatim: strings("Latest timeline"))
        }
      }
      if records.count > 1 {
        Section {
          ForEach(records.dropLast().reversed()) { record in
            DisclosureGroup {
              RecordDetail(record: record, prefix: "log.\(record.sequence)")
            } label: {
              Text(
                verbatim: "#\(record.sequence) \(Self.stamp(record.callDate)) · \(record.fajrName)"
              )
              .font(.footnote.monospaced())
            }
          }
        } header: {
          Text(verbatim: strings("Earlier timelines"))
        }
      }
      if !records.isEmpty {
        Section {
          Text(verbatim: records.map(Self.summary).joined(separator: "\n"))
            .font(.caption2.monospaced())
            .textSelection(.enabled)
            .accessibilityIdentifier("log.all")
        } header: {
          Text(verbatim: strings("Every record"))
        }
      }
    }
    .navigationTitle(Text(verbatim: strings("Widget log")))
    .navigationBarTitleDisplayMode(.inline)
    .environment(\.layoutDirection, .leftToRight)
    .task {
      while !Task.isCancelled {
        reload()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  private func reload() {
    records = DiagnosticsLog().load()
  }

  /// A record on one line: sequence, call, family, settings, Fajr's name, entries, generation
  /// time and footprint.
  static func summary(_ record: DiagnosticsRecord) -> String {
    let before = record.footprintBefore.map { "\($0 / 1_024) KiB" } ?? "–"
    let after = record.footprintAfter.map { "\($0 / 1_024) KiB" } ?? "–"
    return
      "#\(record.sequence) \(stamp(record.callDate)) \(record.family) "
      + "\(record.settingsSummary ?? "none") \(record.fajrName) entries=\(record.entryCount) "
      + String(format: "%.2f ms ", record.generationMilliseconds) + "\(before)->\(after)"
  }

  /// An ISO 8601 instant with the device's offset, as the log's dates are compared with the
  /// device's clock.
  static func stamp(_ date: Date?) -> String {
    guard let date else { return "–" }
    return date.formatted(Date.ISO8601FormatStyle(timeZone: .current))
  }
}

/// Every field of a record, one line each, in the log's own (untranslated) terms.
private struct RecordDetail: View {
  let record: DiagnosticsRecord
  let prefix: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      line("call", "#\(record.sequence) \(WidgetLogView.stamp(record.callDate)) \(record.family)")
      line("fingerprint", record.settingsFingerprint)
      line("settings", record.settingsSummary ?? "none")
      line("locale", record.localeIdentifier)
      line("fajrName", record.fajrName)
      line("names", record.names.joined(separator: " "))
      line("entryCount", "\(record.entryCount)")
      line("first", WidgetLogView.stamp(record.firstEntryDate))
      line("last", WidgetLogView.stamp(record.lastEntryDate))
      line("validUntil", WidgetLogView.stamp(record.validUntil))
      line("reloadDate", WidgetLogView.stamp(record.reloadDate))
      line("truncated", "\(record.isTruncated)")
      line("states", record.states)
      line("generation", String(format: "%.2f ms", record.generationMilliseconds))
      line(
        "footprint",
        "\(Self.megabytes(record.footprintBefore)) → \(Self.megabytes(record.footprintAfter))")
      line("entries", record.entries.joined(separator: "\n"))
    }
    .font(.footnote.monospaced())
    .textSelection(.enabled)
  }

  private func line(_ name: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: name)
        .foregroundStyle(.secondary)
      Text(verbatim: value)
        .accessibilityIdentifier("\(prefix).\(name)")
    }
  }

  private static func megabytes(_ bytes: UInt64?) -> String {
    guard let bytes else { return "–" }
    return String(format: "%.2f MB", Double(bytes) / 1_048_576)
  }
}
