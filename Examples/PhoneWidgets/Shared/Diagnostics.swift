import Darwin
import Foundation
import SalahCore
import SalahWidgets
import os

// DIAGNOSTICS: the example's evidence channel, not part of a widget's job.
//
// On every timeline the extension appends what it read, what it produced and what that cost to a
// bounded log in the App Group, and writes the same line to the unified log. The app's "Widget
// log" screen shows it, the UI tests read it, and the seven-day device soak records it. An app
// built on this example can delete this file and the two lines that call it.

/// One `getTimeline` call of the extension.
nonisolated struct DiagnosticsRecord: Codable, Hashable, Sendable, Identifiable {
  /// The call's number, counting every call since the log was created; the log keeps the last
  /// ``DiagnosticsLog/capacity``.
  var sequence: Int
  /// When the call ran, by the extension's clock.
  var callDate: Date
  /// The widget family WidgetKit asked for.
  var family: String
  /// The fingerprint of the settings the extension read (`WidgetSettings.fingerprint`), or
  /// `"none"`.
  var settingsFingerprint: String
  /// The settings in a few words, or `nil` without settings.
  var settingsSummary: String?
  /// The locale the extension looked the names up in.
  var localeIdentifier: String
  /// The names it resolved, Fajr through Isha, through `PrayerNames(locale:)` in the extension's
  /// process.
  var names: [String]
  /// How many entries the timeline has.
  var entryCount: Int
  var firstEntryDate: Date?
  var lastEntryDate: Date?
  /// SalahWidgets' `validUntil` and `reloadDate`; `nil` for the setup prompt.
  var validUntil: Date?
  var reloadDate: Date?
  var isTruncated: Bool
  /// How many entries of each kind: `available 9 · partial 0 · unavailable 0 · expired 1 ·
  /// setup 0`.
  var states: String
  /// Each entry's date in the place's zone and what it shows.
  var entries: [String]
  /// The time the provider took to build the timeline, measured with `ContinuousClock`.
  var generationMilliseconds: Double
  /// The extension's memory footprint (`TASK_VM_INFO` `phys_footprint`) before and after.
  var footprintBefore: UInt64?
  var footprintAfter: UInt64?

  var id: Int { sequence }

  /// Fajr's name as the extension resolved it.
  var fajrName: String { names.first ?? "" }
}

/// The bounded log of ``DiagnosticsRecord``s: a JSON file in the App Group's container.
///
/// The extension is its only writer; the app only reads it. The file is replaced atomically, so
/// a reader never sees half a write, and the extension's own concurrent calls take turns.
nonisolated struct DiagnosticsLog: Sendable {
  /// How many records the log keeps.
  static let capacity = 200

  /// The log file, or `nil` when the App Group's container isn't available.
  let fileURL: URL?

  private static let lock = OSAllocatedUnfairLock()

  /// The log in the App Group's container.
  init(appGroup: String = PhoneWidgetsID.appGroup) {
    fileURL = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent("diagnostics.v1.json")
  }

  /// A log in a file of your choice, for tests.
  init(fileURL: URL?) {
    self.fileURL = fileURL
  }

  /// The records, oldest first.
  func load() -> [DiagnosticsRecord] {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? Self.decoder.decode([DiagnosticsRecord].self, from: data)) ?? []
  }

  /// Appends a record made for the next sequence number, dropping the oldest beyond
  /// ``capacity``.
  func append(_ make: (_ sequence: Int) -> DiagnosticsRecord) {
    guard let fileURL else { return }
    Self.lock.withLockUnchecked {
      var records = load()
      records.append(make((records.last?.sequence ?? 0) + 1))
      records.removeFirst(max(0, records.count - Self.capacity))
      if let data = try? Self.encoder.encode(records) {
        try? data.write(to: fileURL, options: .atomic)
      }
    }
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

/// Runs the provider and records the call: what the extension's `getTimeline` does.
nonisolated enum TimelineDiagnostics {
  static let logger = Logger(subsystem: PhoneWidgetsID.logSubsystem, category: "timeline")

  /// The provider's timeline for `settings` at `now`, after appending its record to `log` and
  /// writing it to the unified log.
  static func timeline(
    settings: WidgetSettings?, now: Date, family: String, deviceLanguage: NamesLanguage,
    log: DiagnosticsLog
  ) -> WidgetTimeline {
    let before = MemoryFootprint.current()
    let clock = ContinuousClock()
    let start = clock.now
    let timeline = PrayerTimelineProvider.timeline(
      settings: settings, now: now, deviceLanguage: deviceLanguage)
    let elapsed = clock.now - start
    let after = MemoryFootprint.current()

    let strings = WidgetStrings(language: settings?.language ?? deviceLanguage)
    let names = PrayerKind.allCases.map { strings.names.name(of: $0) }
    let milliseconds =
      Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    let zone = settings?.place.location.timeZone ?? .gmt
    var sequence = 0
    log.append { next in
      sequence = next
      return DiagnosticsRecord(
        sequence: next, callDate: now, family: family,
        settingsFingerprint: settings?.fingerprint ?? "none", settingsSummary: settings?.summary,
        localeIdentifier: strings.names.locale.identifier, names: names,
        entryCount: timeline.entries.count, firstEntryDate: timeline.entries.first?.date,
        lastEntryDate: timeline.entries.last?.date,
        validUntil: timeline.prayerTimeline?.validUntil,
        reloadDate: timeline.prayerTimeline?.reloadDate,
        isTruncated: timeline.prayerTimeline?.isTruncated ?? false,
        states: EntrySummary.counts(timeline.entries),
        entries: timeline.entries.map { EntrySummary.line($0, in: zone) },
        generationMilliseconds: milliseconds, footprintBefore: before, footprintAfter: after)
    }
    let reload = timeline.prayerTimeline?.reloadDate.formatted(.iso8601) ?? "never"
    // Notice, not info: the unified log keeps notices on a device, where the soak reads them.
    logger.notice(
      """
      getTimeline #\(sequence, privacy: .public) family=\(family, privacy: .public) \
      settings=\(settings?.fingerprint ?? "none", privacy: .public) \
      (\(settings?.summary ?? "none", privacy: .public)) \
      locale=\(strings.names.locale.identifier, privacy: .public) \
      fajr=\(names.first ?? "", privacy: .public) entries=\(timeline.entries.count, privacy: .public) \
      reload=\(reload, privacy: .public) \
      truncated=\(timeline.prayerTimeline?.isTruncated ?? false, privacy: .public) \
      ms=\(milliseconds, format: .fixed(precision: 2), privacy: .public) \
      footprint=\(before ?? 0, privacy: .public)->\(after ?? 0, privacy: .public)
      """)
    return timeline
  }
}

/// Entries in words, for the log.
nonisolated enum EntrySummary {
  /// How many entries of each kind.
  static func counts(_ entries: [PrayerEntry]) -> String {
    var available = 0
    var partial = 0
    var unavailable = 0
    var expired = 0
    var setup = 0
    for entry in entries {
      switch WidgetDisplay(entry.content) {
      case .times(let times): if times.isPartial { partial += 1 } else { available += 1 }
      case .unavailable: unavailable += 1
      case .expired: expired += 1
      case .setupRequired: setup += 1
      }
    }
    return
      "available \(available) · partial \(partial) · unavailable \(unavailable) · "
      + "expired \(expired) · setup \(setup)"
  }

  /// An entry's date in `zone` and what it shows: `2026-10-14 15:27 next maghrib@17:57`.
  static func line(_ entry: PrayerEntry, in zone: TimeZone) -> String {
    let date = stamp(entry.date, in: zone)
    switch WidgetDisplay(entry.content) {
    case .setupRequired:
      return "\(date) setup required"
    case .unavailable(let reason):
      return "\(date) unavailable (\(reason))"
    case .expired(let knownThrough):
      return "\(date) expired (known through \(stamp(knownThrough, in: zone)))"
    case .times(let times):
      let next = times.state.nextPrayer.map { "\($0.kind.rawValue)@\(clock($0.time, in: zone))" }
      let missing =
        times.missingKinds.isEmpty
        ? "" : " missing \(times.missingKinds.map(\.rawValue).joined(separator: ","))"
      return "\(date) next \(next ?? "unknown")\(missing)"
    }
  }

  private static func stamp(_ date: Date, in zone: TimeZone) -> String {
    date.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: zone, calendar: Calendar(identifier: .gregorian)))
  }

  private static func clock(_ date: Date, in zone: TimeZone) -> String {
    date.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: zone, calendar: Calendar(identifier: .gregorian)))
  }
}

/// The process's memory footprint, as Xcode's memory gauge and the system's extension limits
/// count it.
nonisolated enum MemoryFootprint {
  /// `phys_footprint` from `task_info(TASK_VM_INFO)`, in bytes, or `nil` if the call fails.
  static func current() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : nil
  }
}
