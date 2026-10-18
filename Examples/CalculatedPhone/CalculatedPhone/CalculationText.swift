import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// One parameter of the calculation, as the Calculation section shows it.
nonisolated struct ParameterRow: Equatable, Identifiable, Sendable {
  /// A stable name, used in the accessibility identifier `calc.<id>`.
  var id: String
  var title: String
  var value: String
  /// The value in words for VoiceOver: "90 minutes after Maghrib" where the screen shows
  /// "90 min after Maghrib".
  var spokenValue: String

  init(id: String, title: String, value: String, spokenValue: String? = nil) {
    self.id = id
    self.title = title
    self.value = value
    self.spokenValue = spokenValue ?? value
  }

  /// What VoiceOver reads for the row: "Isha: 90 minutes after Maghrib".
  var accessibilityLabel: String { "\(title): \(spokenValue)" }
}

/// Words for SalahTimes' parameters, in the app's language.
nonisolated struct CalculationText: Sendable {
  let strings: PhoneStrings
  let format: PhoneFormat

  init(strings: PhoneStrings) {
    self.strings = strings
    format = PhoneFormat(strings: strings, timeZone: .gmt)
  }

  /// Every parameter of the settings, in the order SalahTimes declares them.
  func rows(_ settings: AppSettings) -> [ParameterRow] {
    let parameters = settings.calculation.parameters
    return [
      ParameterRow(id: "method", title: strings("Method"), value: name(of: settings.method)),
      ParameterRow(id: "fajr", title: strings("Fajr"), value: text(parameters.fajr)),
      ParameterRow(id: "maghrib", title: strings("Maghrib"), value: text(parameters.maghrib)),
      ParameterRow(
        id: "isha", title: strings("Isha"), value: text(parameters.isha),
        spokenValue: spokenText(parameters.isha)),
      ParameterRow(
        id: "madhab", title: strings("Asr (madhab)"), value: name(of: parameters.madhab)),
      ParameterRow(
        id: "highLatitudeRule", title: strings("High latitudes"),
        value: name(of: parameters.highLatitudeRule)),
      ParameterRow(id: "nightSpan", title: strings("Night"), value: name(of: parameters.nightSpan)),
      ParameterRow(
        id: "methodAdjustments", title: strings("Method's minutes"),
        value: text(parameters.methodAdjustments),
        spokenValue: spokenText(parameters.methodAdjustments)),
      ParameterRow(
        id: "adjustments", title: strings("Your minutes"), value: text(parameters.adjustments),
        spokenValue: spokenText(parameters.adjustments)),
      ParameterRow(
        id: "rounding", title: strings("Rounding"), value: name(of: parameters.rounding)),
      ParameterRow(
        id: "ramadanIsha", title: strings("Ramadan Isha"), value: text(parameters.ramadanIsha),
        spokenValue: spokenText(parameters.ramadanIsha)),
    ]
  }

  func name(of choice: MethodChoice) -> String {
    switch choice {
    case .preset(let method): name(of: method)
    case .custom: strings("Custom")
    }
  }

  func name(of method: CalculationMethod) -> String {
    switch method {
    case .muslimWorldLeague: strings("Muslim World League")
    case .isna: strings("ISNA (North America)")
    case .egyptian: strings("Egyptian General Authority of Survey")
    case .ummAlQura: strings("Umm al-Qura")
    case .karachi: strings("University of Islamic Sciences, Karachi")
    case .tehran: strings("Institute of Geophysics, Tehran")
    case .diyanet: strings("Diyanet (Turkey)")
    case .dubai: strings("Dubai (UAE)")
    case .kuwait: strings("Kuwait")
    case .qatar: strings("Qatar")
    case .muis: strings("MUIS (Singapore)")
    case .jakim: strings("JAKIM (Malaysia)")
    case .kemenag: strings("Kemenag (Indonesia)")
    case .moonsightingCommittee: strings("Moonsighting Committee")
    }
  }

  func name(of madhab: Madhab) -> String {
    switch madhab {
    case .shafi: strings("Shafi'i")
    case .hanafi: strings("Hanafi")
    }
  }

  func name(of rule: HighLatitudeRule) -> String {
    switch rule {
    case .recommended: strings("Recommended")
    case .middleOfTheNight: strings("Middle of the night")
    case .seventhOfTheNight: strings("Seventh of the night")
    case .twilightAngle: strings("Twilight angle")
    case .disabled: strings("None")
    }
  }

  func name(of span: NightSpan) -> String {
    switch span {
    case .sunsetToFajr: strings("Sunset to Fajr")
    case .sunsetToSunrise: strings("Sunset to sunrise")
    }
  }

  func name(of rounding: Rounding) -> String {
    switch rounding {
    case .nearest: strings("Nearest minute")
    case .up: strings("Up to the minute")
    case .none: strings("None (seconds kept)")
    }
  }

  func name(of shafaq: Shafaq) -> String {
    switch shafaq {
    case .general: strings("general twilight")
    case .ahmer: strings("red twilight")
    case .abyad: strings("white twilight")
    }
  }

  /// An angle below the horizon: "18.5°".
  func degrees(_ value: Double) -> String {
    strings("\(format.number(value))°")
  }

  /// A number of minutes: "90 min".
  func minutes(_ value: Int) -> String {
    strings("\(format.number(Double(value))) min")
  }

  /// A number of minutes in words, for VoiceOver: "90 minutes".
  func spokenMinutes(_ value: Int) -> String {
    format.spokenMinutes(value)
  }

  func text(_ rule: FajrRule) -> String {
    switch rule {
    case .angle(let value): degrees(value)
    case .moonsightingCommittee: strings("Moonsighting Committee")
    }
  }

  func text(_ rule: MaghribRule) -> String {
    switch rule {
    case .sunset: strings("Sunset")
    case .angle(let value): degrees(value)
    }
  }

  func text(_ rule: IshaRule) -> String {
    switch rule {
    case .angle(let value): degrees(value)
    case .minutesAfterMaghrib(let value):
      strings("\(format.number(Double(value))) min after Maghrib")
    case .moonsightingCommittee(let shafaq):
      strings("Moonsighting Committee, \(name(of: shafaq))")
    }
  }

  func text(_ adjustments: PrayerAdjustments) -> String {
    let items = Self.minutes(adjustments).map { kind, value in
      strings("\(strings.names.name(of: kind)) \(format.signed(value)) min")
    }
    return items.isEmpty ? strings("None") : format.units(items)
  }

  /// The minutes in words, for VoiceOver: "Sunrise −7 minutes, Dhuhr +5 minutes".
  func spokenText(_ adjustments: PrayerAdjustments) -> String {
    let items = Self.minutes(adjustments).map { kind, value in
      strings("\(strings.names.name(of: kind)) \(format.spokenMinutes(value, signed: true))")
    }
    return items.isEmpty ? strings("None") : format.units(items)
  }

  /// The kinds with minutes other than zero, Fajr through Isha.
  private static func minutes(_ adjustments: PrayerAdjustments) -> [(PrayerKind, Int)] {
    let minutes: [(PrayerKind, Int)] = [
      (.fajr, adjustments.fajr), (.sunrise, adjustments.sunrise), (.dhuhr, adjustments.dhuhr),
      (.asr, adjustments.asr), (.maghrib, adjustments.maghrib), (.isha, adjustments.isha),
    ]
    return minutes.filter { $0.1 != 0 }
  }

  /// The Isha rule in words, for VoiceOver: "90 minutes after Maghrib".
  func spokenText(_ rule: IshaRule) -> String {
    if case .minutesAfterMaghrib(let value) = rule {
      return strings("\(format.spokenMinutes(value)) after Maghrib")
    }
    return text(rule)
  }

  /// The Ramadan rule in words, for VoiceOver: "120 minutes after Maghrib in Ramadan".
  func spokenText(_ rule: RamadanIshaRule) -> String {
    switch rule {
    case .off:
      return text(rule)
    case .interval(let minutes, 0):
      return strings("\(format.spokenMinutes(minutes)) after Maghrib in Ramadan")
    case .interval(let minutes, let offset):
      return strings(
        "\(format.spokenMinutes(minutes)) after Maghrib in Ramadan, Hijri day offset \(format.signed(offset))"
      )
    }
  }

  func text(_ rule: RamadanIshaRule) -> String {
    switch rule {
    case .off:
      return strings("Off")
    case .interval(let minutes, 0):
      return strings("\(format.number(Double(minutes))) min after Maghrib in Ramadan")
    case .interval(let minutes, let offset):
      return strings(
        "\(format.number(Double(minutes))) min after Maghrib in Ramadan, Hijri day offset \(format.signed(offset))"
      )
    }
  }
}
