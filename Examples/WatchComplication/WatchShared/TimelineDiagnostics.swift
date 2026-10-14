import Darwin
import Foundation
import SalahWidgets
import os

/// One timeline the complication extension gave WidgetKit: the evidence that the extension ran,
/// what it read and what it built.
///
/// This is a diagnostics channel for the example, kept small: the extension appends a record
/// for every `getTimeline` call and keeps the latest ``TimelineLog/limit``.
nonisolated struct TimelineRecord: Codable, Equatable, Sendable {
  /// When WidgetKit asked for the timeline.
  var requestedAt: Date
  /// The complication family WidgetKit asked for, such as `accessoryCircular`.
  var family: String
  /// The fingerprint of the inputs the extension read, or `"none"`.
  var inputs: String
  /// How many entries the timeline has.
  var entryCount: Int
  /// The first entry's date.
  var firstEntry: Date?
  /// The last entry's date.
  var lastEntry: Date?
  /// Where the timeline's validity ends: the timeline-expired entry's date, if there is one.
  var validUntil: Date?
  /// How many entries show each display, such as `next×9 timelineExpired×1`.
  var states: String
  /// How long building the timeline took, in milliseconds.
  var milliseconds: Double
  /// The extension's memory footprint after building it, in megabytes, if known.
  var footprintMegabytes: Double?

  /// A record of a timeline built from `inputs` at `requestedAt`.
  init(
    requestedAt: Date, family: String, inputs: WatchInputs?, entries: [ComplicationEntry],
    milliseconds: Double, footprintMegabytes: Double?
  ) {
    self.requestedAt = requestedAt
    self.family = family
    self.inputs = inputs?.fingerprint ?? "none"
    entryCount = entries.count
    firstEntry = entries.first?.date
    lastEntry = entries.last?.date
    validUntil =
      entries.compactMap { entry -> Date? in
        if case .timeline(.expired(let knownThrough)) = entry.content { return knownThrough }
        return nil
      }.last
    var counts: [String: Int] = [:]
    var order: [String] = []
    for entry in entries {
      let summary = ComplicationDisplay(entry.content, at: entry.date).summary
      if counts[summary] == nil { order.append(summary) }
      counts[summary, default: 0] += 1
    }
    states = order.map { "\($0)×\(counts[$0] ?? 0)" }.joined(separator: " ")
    self.milliseconds = milliseconds
    self.footprintMegabytes = footprintMegabytes
  }

  /// The record as one log line.
  var line: String {
    let iso = Date.ISO8601FormatStyle()
    let dates = [firstEntry, lastEntry, validUntil].map { $0.map(iso.format) ?? "-" }
    let footprint = footprintMegabytes.map { String(format: "%.1f MB", $0) } ?? "-"
    return "timeline family=\(family) inputs=\(inputs) entries=\(entryCount) "
      + "first=\(dates[0]) last=\(dates[1]) validUntil=\(dates[2]) states=[\(states)] "
      + String(format: "built=%.1f ms ", milliseconds) + "footprint=\(footprint)"
  }
}

/// The complication extension's bounded record of its timelines, in the watch's App Group.
nonisolated struct TimelineLog: Sendable {
  /// The most records kept; older ones are dropped.
  static let limit = 50

  /// Where the records are stored.
  var store: SharedValue<[TimelineRecord]> = .timelineLog

  /// The records, oldest first.
  func records() -> [TimelineRecord] {
    store.load() ?? []
  }

  /// Appends a record, keeping the latest ``limit``.
  func append(_ record: TimelineRecord) {
    var records = records()
    records.append(record)
    _ = try? store.save(Array(records.suffix(Self.limit)))
  }

  /// The log for the extension's `os.Logger` lines.
  static let logger = Logger(subsystem: WatchStorage.subsystem, category: "timeline")
}

/// The process's memory footprint, as the system counts it against its limit, in megabytes.
nonisolated func memoryFootprintMegabytes() -> Double? {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  guard result == KERN_SUCCESS else { return nil }
  return Double(info.phys_footprint) / 1_048_576
}
