import Foundation

/// Localized prayer names and abbreviations for an explicit locale.
///
/// `PrayerNames` reads the package's String Catalog in the locale you pass, whatever the
/// process language is, so an app can show Arabic names while it runs in English:
///
/// ```swift
/// let names = PrayerNames(locale: Locale(identifier: "ar"))
/// names.name(of: .fajr)            // "الفجر"
/// names.abbreviation(of: .fajr)    // "فج"
/// ```
///
/// Languages match from the most specific form of the locale to the least
/// (language-script-region, language-script, language-region, language), then fall back to
/// English. The catalog has Arabic, Bengali, English, French, Indonesian, Malay, Persian,
/// Turkish and Urdu. Entries a native speaker hasn't reviewed yet carry the catalog's
/// `needs_review` state.
///
/// Jumu'ah is declared, never inferred: ``name(of:)-(PrayerEvent)`` uses the Jumu'ah name only
/// when the event's ``PrayerEvent/observance`` is ``PrayerObservance/jumuah``. A Friday alone
/// never renames Dhuhr.
nonisolated public struct PrayerNames: Sendable {
  /// One string in the vocabulary, for overrides and direct lookup.
  public enum Entry: Hashable, Sendable {
    /// The name of a kind, such as "Fajr".
    case name(PrayerKind)
    /// The abbreviation of a kind, such as "F".
    case abbreviation(PrayerKind)
    /// The name of Friday's congregational prayer, used in place of Dhuhr when declared.
    case jumuah
    /// The abbreviation of Friday's congregational prayer.
    case jumuahAbbreviation
  }

  /// The locale the names are looked up in.
  public let locale: Locale

  private let overrides: [Entry: String]
  private let catalog: StringCatalog?
  private let languages: [String]

  /// Creates names for a locale.
  ///
  /// - Parameters:
  ///   - locale: The locale to look names up in. Only its language, script and region matter.
  ///   - overrides: Values that replace the catalog's, entry by entry; for example a mosque's
  ///     preferred spelling of Dhuhr.
  public init(locale: Locale, overrides: [Entry: String] = [:]) {
    self.init(locale: locale, overrides: overrides, catalog: StringCatalog.bundled)
  }

  /// Creates names that read from the given catalog; `nil` stands for a missing resource.
  init(locale: Locale, overrides: [Entry: String], catalog: StringCatalog?) {
    self.locale = locale
    self.overrides = overrides
    self.catalog = catalog
    self.languages = StringCatalog.candidates(for: locale)
  }

  /// The name of an event: the Jumu'ah name when the event's observance declares Jumu'ah,
  /// otherwise the name of its kind.
  public func name(of event: PrayerEvent) -> String {
    string(for: event.observance == .jumuah ? .jumuah : .name(event.kind))
  }

  /// The name of a kind, such as "Fajr" or "الفجر".
  public func name(of kind: PrayerKind) -> String {
    string(for: .name(kind))
  }

  /// The abbreviation of an event: the Jumu'ah abbreviation when the event's observance
  /// declares Jumu'ah, otherwise the abbreviation of its kind.
  public func abbreviation(of event: PrayerEvent) -> String {
    string(for: event.observance == .jumuah ? .jumuahAbbreviation : .abbreviation(event.kind))
  }

  /// The abbreviation of a kind, such as "F" or "فج", for compact layouts.
  public func abbreviation(of kind: PrayerKind) -> String {
    string(for: .abbreviation(kind))
  }

  /// The value of an entry: its override if there is one, otherwise the catalog's value for the
  /// locale, otherwise English.
  public func string(for entry: Entry) -> String {
    if let override = overrides[entry] {
      return override
    }
    return catalog?.value(for: entry.key, languages: languages) ?? entry.englishFallback
  }
}

nonisolated extension PrayerNames.Entry {
  /// Every entry, in catalog order.
  static let allEntries: [PrayerNames.Entry] =
    PrayerKind.allCases.flatMap { [.name($0), .abbreviation($0)] } + [.jumuah, .jumuahAbbreviation]

  /// The catalog key, following Salah's catalog: `prayer.<kind>`, `prayer.<kind>.abbr`,
  /// `prayer.dhuhr.jumuah` and `prayer.dhuhr.jumuah.abbr`.
  var key: String {
    switch self {
    case .name(let kind): "prayer.\(kind.rawValue)"
    case .abbreviation(let kind): "prayer.\(kind.rawValue).abbr"
    case .jumuah: "prayer.dhuhr.jumuah"
    case .jumuahAbbreviation: "prayer.dhuhr.jumuah.abbr"
    }
  }

  /// The English value, used when the catalog resource is missing or unreadable, so a name never
  /// comes back as its raw key.
  var englishFallback: String {
    switch self {
    case .name(let kind):
      switch kind {
      case .fajr: "Fajr"
      case .sunrise: "Sunrise"
      case .dhuhr: "Dhuhr"
      case .asr: "Asr"
      case .maghrib: "Maghrib"
      case .isha: "Isha"
      }
    case .abbreviation(let kind):
      switch kind {
      case .fajr: "F"
      case .sunrise: "S"
      case .dhuhr: "D"
      case .asr: "A"
      case .maghrib: "M"
      case .isha: "I"
      }
    case .jumuah: "Jumuah"
    case .jumuahAbbreviation: "J"
    }
  }
}
