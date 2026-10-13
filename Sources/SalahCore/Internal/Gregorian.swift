import Foundation

/// Proleptic Gregorian day arithmetic without `Calendar`, so day math is exact and identical on
/// every platform. The algorithms are Howard Hinnant's `days_from_civil` and `civil_from_days`.
nonisolated enum Gregorian {
  /// Days from 1970-01-01 to the given date. Months outside 1...12 roll into adjacent years,
  /// and days outside the month roll into adjacent months.
  static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
    let monthIndex = month - 1
    let normalizedYear = year + floorDivision(monthIndex, 12)
    let normalizedMonth = floorModulo(monthIndex, 12) + 1
    return daysFromCivil(normalizedYear, normalizedMonth, 1) + (day - 1)
  }

  /// The date `days` days after 1970-01-01.
  static func date(daysSinceEpoch days: Int) -> (year: Int, month: Int, day: Int) {
    let shifted = days + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra =
      (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
  }

  static func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12: return 31
    case 4, 6, 9, 11: return 30
    case 2: return isLeapYear(year) ? 29 : 28
    default: return 0
    }
  }

  static func floorDivision(_ value: Int, _ divisor: Int) -> Int {
    let quotient = value / divisor
    return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
  }

  static func floorModulo(_ value: Int, _ divisor: Int) -> Int {
    value - floorDivision(value, divisor) * divisor
  }

  private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
    let yearOfEra = shiftedYear - era * 400
    let shiftedMonth = (month + 9) % 12
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }
}
