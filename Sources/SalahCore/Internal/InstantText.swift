import Foundation

/// Strict ISO 8601 date-time text for instants, independent of locale and platform formatters.
///
/// Parses `YYYY-MM-DDTHH:MM[:SS[.fraction]](Z|±HH:MM|±HHMM|±HH)`; formats UTC as
/// `YYYY-MM-DDTHH:MM:SSZ`, adding milliseconds only when the instant has them.
nonisolated enum InstantText {
  static func parse(_ text: String) -> Date? {
    let characters = Array(text.utf8)
    var index = 0

    func digits(_ count: Int) -> Int? {
      guard index + count <= characters.count else { return nil }
      var value = 0
      for offset in 0..<count {
        let character = characters[index + offset]
        guard character >= 0x30, character <= 0x39 else { return nil }
        value = value * 10 + Int(character - 0x30)
      }
      index += count
      return value
    }

    func expect(_ character: UInt8) -> Bool {
      guard index < characters.count, characters[index] == character else { return false }
      index += 1
      return true
    }

    guard let year = digits(4), expect(0x2D), let month = digits(2), expect(0x2D),
      let day = digits(2), expect(0x54) || expect(0x74),
      let hour = digits(2), expect(0x3A), let minute = digits(2)
    else { return nil }

    var second = 0
    var fraction = 0.0
    if expect(0x3A) {
      guard let parsedSecond = digits(2) else { return nil }
      second = parsedSecond
      if expect(0x2E) || expect(0x2C) {
        var scale = 0.1
        var sawDigit = false
        while index < characters.count, characters[index] >= 0x30, characters[index] <= 0x39 {
          fraction += Double(characters[index] - 0x30) * scale
          scale /= 10
          index += 1
          sawDigit = true
        }
        guard sawDigit else { return nil }
      }
    }

    var offsetSeconds = 0
    if expect(0x5A) || expect(0x7A) {
      offsetSeconds = 0
    } else if index < characters.count, characters[index] == 0x2B || characters[index] == 0x2D {
      let sign = characters[index] == 0x2D ? -1 : 1
      index += 1
      guard let offsetHours = digits(2) else { return nil }
      var offsetMinutes = 0
      if expect(0x3A) {
        guard let parsed = digits(2) else { return nil }
        offsetMinutes = parsed
      } else if let parsed = digits(2) {
        offsetMinutes = parsed
      }
      guard offsetHours <= 23, offsetMinutes <= 59 else { return nil }
      offsetSeconds = sign * (offsetHours * 3_600 + offsetMinutes * 60)
    } else {
      return nil
    }

    guard index == characters.count,
      (1...12).contains(month),
      (1...Gregorian.daysInMonth(year: year, month: month)).contains(day),
      (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
    else { return nil }

    let days = Gregorian.daysSinceEpoch(year: year, month: month, day: day)
    let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
    return Date(timeIntervalSince1970: Double(seconds) + fraction)
  }

  /// Formats to the nearest millisecond, so text parsed from milliseconds round-trips exactly.
  static func format(_ date: Date) -> String {
    let milliseconds = Int((Gregorian.clampedSeconds(date.timeIntervalSince1970) * 1_000).rounded())
    let seconds = Gregorian.floorDivision(milliseconds, 1_000)
    let millisecond = Gregorian.floorModulo(milliseconds, 1_000)
    let days = Gregorian.floorDivision(seconds, 86_400)
    let secondOfDay = Gregorian.floorModulo(seconds, 86_400)
    let civil = Gregorian.date(daysSinceEpoch: days)
    var text =
      "\(pad(civil.year, 4))-\(pad(civil.month, 2))-\(pad(civil.day, 2))T"
      + "\(pad(secondOfDay / 3_600, 2)):\(pad(secondOfDay % 3_600 / 60, 2)):"
      + "\(pad(secondOfDay % 60, 2))"
    if millisecond != 0 { text += ".\(pad(millisecond, 3))" }
    return text + "Z"
  }

  static func pad(_ value: Int, _ width: Int) -> String {
    let text = String(abs(value))
    let padded =
      text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    return value < 0 ? "-" + padded : padded
  }
}
