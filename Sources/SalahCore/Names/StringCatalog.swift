import Foundation

/// The package's String Catalog, `Resources/Localizable.xcstrings`, read as JSON.
///
/// The catalog ships as a copied resource and is decoded with `JSONDecoder` on every platform,
/// because the compiled-catalog lookup doesn't exist on Linux and returns keys under SwiftPM
/// before 6.4 (RFC 0001, §6.1). Xcode 26 compiles the catalog despite `.copy`, so a build in an
/// Xcode 26 project reads the compiled tables instead. Only the parts a lookup needs are
/// decoded; plural and device variations are ignored.
nonisolated struct StringCatalog: Decodable, Equatable, Sendable {
  /// A string unit: one translated value and its review state.
  struct StringUnit: Decodable, Equatable, Sendable {
    /// `translated`, `needs_review`, or another String Catalog state; `nil` when the value comes
    /// from a compiled table, which doesn't keep it.
    var state: String?
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
  ///
  /// Without the copied file, the catalog comes from the tables Xcode 26 compiles it into.
  static let bundled: StringCatalog? = {
    guard let url = resourceURL else {
      return Bundle.module.resourceURL.flatMap { compiled(in: $0) }
    }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(StringCatalog.self, from: data)
  }()

  /// The catalog rebuilt from the tables `xcstringstool compile` writes into `directory`, one
  /// `<language>.lproj/Localizable.strings` property list per language, or `nil` when there are
  /// none. Comments and review states don't survive compilation.
  static func compiled(in directory: URL, sourceLanguage: String = "en") -> StringCatalog? {
    let folders =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    var strings: [String: Entry] = [:]
    for folder in folders where folder.pathExtension == "lproj" {
      let table = folder.appendingPathComponent("Localizable.strings")
      guard let data = try? Data(contentsOf: table),
        let values = try? PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: String]
      else { continue }
      let language = folder.deletingPathExtension().lastPathComponent
      for (key, value) in values {
        strings[key, default: Entry()].localizations[language] = Localization(
          stringUnit: StringUnit(state: nil, value: value))
      }
    }
    return strings.isEmpty ? nil : StringCatalog(sourceLanguage: sourceLanguage, strings: strings)
  }

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
