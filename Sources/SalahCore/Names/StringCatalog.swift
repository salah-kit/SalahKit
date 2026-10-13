import Foundation

/// The package's String Catalog, `Resources/Localizable.xcstrings`, read as JSON.
///
/// The catalog ships as a copied resource and is decoded with `JSONDecoder` on every platform,
/// because the compiled-catalog lookup doesn't exist on Linux and returns keys under SwiftPM
/// before 6.4 (RFC 0001, §6.1). Only the parts a lookup needs are decoded; plural and device
/// variations are ignored.
nonisolated struct StringCatalog: Decodable, Equatable, Sendable {
  /// A string unit: one translated value and its review state.
  struct StringUnit: Decodable, Equatable, Sendable {
    /// `translated`, `needs_review`, or another String Catalog state.
    var state: String
    /// The translated text.
    var value: String
  }

  /// One language's translation of a key.
  struct Localization: Decodable, Equatable, Sendable {
    /// `nil` when the translation uses variations instead of a single string unit.
    var stringUnit: StringUnit?
  }

  /// One key's translations, keyed by language identifier (`en`, `ar`, `zh-Hant`, `pt-BR`).
  struct Entry: Decodable, Equatable, Sendable {
    var comment: String?
    var localizations: [String: Localization]

    private enum CodingKeys: String, CodingKey {
      case comment, localizations
    }

    init(comment: String? = nil, localizations: [String: Localization] = [:]) {
      self.comment = comment
      self.localizations = localizations
    }

    /// Xcode writes a key without `localizations` until it has a translation, so a missing
    /// field reads as empty instead of failing the whole catalog.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      comment = try container.decodeIfPresent(String.self, forKey: .comment)
      localizations =
        try container.decodeIfPresent([String: Localization].self, forKey: .localizations) ?? [:]
    }
  }

  /// The language whose values are the fallback, `en` for this package.
  var sourceLanguage: String
  /// The entries, keyed by string key.
  var strings: [String: Entry]

  /// The location of the bundled catalog, or `nil` when the resource is missing.
  static var resourceURL: URL? {
    Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
  }

  /// The bundled catalog, decoded once, or `nil` when it's missing or unreadable.
  static let bundled: StringCatalog? = {
    guard let url = resourceURL, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(StringCatalog.self, from: data)
  }()

  /// The value of `key` for `locale`, trying ``candidates(for:)`` in order and then the source
  /// language. Returns `nil` when the key is missing or has neither.
  func value(for key: String, locale: Locale) -> String? {
    value(for: key, languages: Self.candidates(for: locale))
  }

  /// The value of `key` for the first of `languages` the entry has, then the source language.
  func value(for key: String, languages: [String]) -> String? {
    guard let entry = strings[key] else { return nil }
    var values: [String: String] = [:]
    for (language, localization) in entry.localizations {
      if let value = localization.stringUnit?.value {
        values[Self.normalized(language)] = value
      }
    }
    for language in languages + [sourceLanguage] {
      if let value = values[Self.normalized(language)] {
        return value
      }
    }
    return nil
  }

  /// The catalog languages to try for a locale, most specific first: language-script-region,
  /// language-script, language-region, language (RFC 0001, §4.9).
  static func candidates(for locale: Locale) -> [String] {
    let language = locale.language
    guard let code = language.languageCode?.identifier, !code.isEmpty else { return [] }
    let script = language.script?.identifier
    let region = language.region?.identifier
    var result: [String] = []
    func add(_ parts: [String?]) {
      guard parts.allSatisfy({ $0 != nil }) else { return }
      let identifier = parts.compactMap { $0 }.joined(separator: "-")
      if !result.contains(identifier) {
        result.append(identifier)
      }
    }
    add([code, script, region])
    add([code, script])
    add([code, region])
    add([code])
    return result
  }

  /// A language identifier in a form that compares equal across case and separator
  /// differences: `pt_BR`, `pt-br` and `pt-BR` all become `pt-br`.
  private static func normalized(_ language: String) -> String {
    language.replacingOccurrences(of: "_", with: "-").lowercased()
  }
}
