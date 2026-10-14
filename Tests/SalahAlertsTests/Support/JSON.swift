import Foundation
import SalahCore

/// A JSON value, for reading vector files whose shapes the tests check field by field.
nonisolated enum JSON: Decodable, Equatable, Sendable, CustomStringConvertible {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSON].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSON].self) {
      self = .object(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else {
      self = .number(try container.decode(Double.self))
    }
  }

  subscript(key: String) -> JSON? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  var string: String? { if case .string(let value) = self { value } else { nil } }
  var number: Double? { if case .number(let value) = self { value } else { nil } }
  var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
  var array: [JSON]? { if case .array(let value) = self { value } else { nil } }
  var object: [String: JSON]? { if case .object(let value) = self { value } else { nil } }
  var isNull: Bool { self == .null }

  var description: String {
    switch self {
    case .null: "null"
    case .bool(let value): "\(value)"
    case .number(let value): "\(value)"
    case .string(let value): "\"\(value)\""
    case .array(let value): "[\(value.map(\.description).joined(separator: ", "))]"
    case .object(let value):
      "{\(value.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", "))}"
    }
  }

  func required(_ key: String) throws -> JSON {
    guard let value = self[key] else { throw VectorError.missing(key, in: self) }
    return value
  }

  func requiredString() throws -> String {
    guard let value = string else { throw VectorError.type("string", self) }
    return value
  }

  func requiredNumber() throws -> Double {
    guard let value = number else { throw VectorError.type("number", self) }
    return value
  }

  func requiredArray() throws -> [JSON] {
    guard let value = array else { throw VectorError.type("array", self) }
    return value
  }

  func instant() throws -> Date {
    guard let text = string, let date = Instant.parse(text) else {
      throw VectorError.type("instant", self)
    }
    return date
  }

  func civilDay() throws -> CivilDay {
    guard let text = string, let day = CivilDay(text) else { throw VectorError.type("day", self) }
    return day
  }

  /// Decodes this value as `type`, through its JSON text.
  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(encoded.utf8))
  }

  /// The value as JSON text.
  var encoded: String {
    switch self {
    case .null: "null"
    case .bool(let value): value ? "true" : "false"
    case .number(let value):
      value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : "\(value)"
    case .string(let value): Self.quoted(value)
    case .array(let value): "[\(value.map(\.encoded).joined(separator: ","))]"
    case .object(let value):
      "{\(value.map { "\(Self.quoted($0.key)):\($0.value.encoded)" }.joined(separator: ","))}"
    }
  }

  private static func quoted(_ text: String) -> String {
    let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
    return String(decoding: data, as: UTF8.self)
  }
}

nonisolated enum VectorError: Error, CustomStringConvertible {
  case missing(String, in: JSON)
  case type(String, JSON)

  var description: String {
    switch self {
    case .missing(let key, let json): "missing key \(key) in \(json)"
    case .type(let type, let value): "expected \(type), found \(value)"
    }
  }
}

/// ISO 8601 instants with an offset or `Z`, as the vectors write them.
nonisolated enum Instant {
  static func parse(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text)
  }

  /// A UTC description to the millisecond, for failure messages.
  static func text(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  /// Milliseconds since 1970, the precision vectors compare instants at.
  static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}

/// The repository's `Vectors` folder and its JSON files.
nonisolated enum VectorFiles {
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Vectors")

  struct Vector: Sendable {
    var file: String
    var id: String
    var input: JSON
    var expected: JSON
  }

  /// Every vector in a folder's JSON files, and the problems loading them.
  static func load(_ folder: String) -> (vectors: [Vector], errors: [String]) {
    var vectors: [Vector] = []
    var errors: [String] = []
    let directory = root.appendingPathComponent(folder)
    let names =
      (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
      .filter { $0.hasSuffix(".json") }.sorted() ?? []
    if names.isEmpty { errors.append("no vector files in \(folder)/") }
    for name in names {
      let path = "\(folder)/\(name)"
      do {
        let file = try JSONDecoder().decode(
          JSON.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
        guard file["schemaVersion"]?.number == 1 else {
          errors.append("\(path): unknown schemaVersion \(file["schemaVersion"] ?? .null)")
          continue
        }
        for vector in try file.required("vectors").requiredArray() {
          vectors.append(
            Vector(
              file: path, id: try vector.required("id").requiredString(),
              input: try vector.required("input"), expected: try vector.required("expected")))
        }
      } catch {
        errors.append("\(path): \(error)")
      }
    }
    return (vectors, errors)
  }
}
