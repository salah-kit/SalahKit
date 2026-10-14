import Foundation
import SalahCore

/// A known event or an explicitly missing kind, before SwiftUI wraps its text.
nonisolated enum ListRowContent: Hashable, Identifiable, Sendable {
  case event(RowContent)
  case missing(day: CivilDay, kind: PrayerKind, reason: ScheduleGapReason, name: String)

  var kind: PrayerKind {
    switch self {
    case .event(let row): row.event.kind
    case .missing(_, let kind, _, _): kind
    }
  }

  var id: String {
    switch self {
    case .event(let row): row.event.id
    case .missing(let day, let kind, _, _): "\(day)/\(kind.rawValue)/missing"
    }
  }

  /// Keeps the original event ordering when no missing rows were requested. Otherwise the
  /// union uses canonical kind order; a known event takes precedence over a conflicting gap.
  static func rows(
    day: PrayerDay, state: PrayerState?, names: PrayerNames, locale: Locale,
    missing: [PrayerKind: ScheduleGapReason]
  ) -> [ListRowContent] {
    let known = RowContent.rows(day: day, state: state, names: names, locale: locale)
    guard !missing.isEmpty else { return known.map(Self.event) }
    let present = Set(known.map { $0.event.kind })
    let gaps = missing.compactMap { kind, reason -> ListRowContent? in
      guard !present.contains(kind) else { return nil }
      return .missing(day: day.day, kind: kind, reason: reason, name: names.name(of: kind))
    }
    return (known.map(Self.event) + gaps).sorted { $0.kind < $1.kind }
  }
}
