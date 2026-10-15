import Foundation
import SalahAlerts
import SalahCore
import SalahTimes

/// Settings read from the launch arguments, for tests and demos. The README lists them.
///
/// Clock and language apply to this run only. The place and calculation arguments change the
/// settings as if they were made in Settings, so they're saved. An argument whose value can't
/// be read is ignored.
nonisolated struct LaunchOptions: Equatable, Sendable {
  /// `-now <ISO 8601 instant>`: start the clock at this instant.
  var now: Date?
  /// `-frozen`: keep the clock at `-now`.
  var frozen = false
  /// `-language en|ar`.
  var language: String?
  /// `-resetSettings`: start from the defaults, ignoring stored settings.
  var resetSettings = false
  /// `-place <preset>`, or `-latitude`, `-longitude` and `-timeZone` together, with optional
  /// `-countryCode` and `-placeName`.
  var place: Place?
  /// `-method <name>`: a `CalculationMethod` raw value such as `ummAlQura`, or `custom`.
  var method: MethodChoice?
  /// `-madhab shafi|hanafi`.
  var madhab: Madhab?
  /// `-highLatitudeRule <name>`: a `HighLatitudeRule` raw value such as `middleOfTheNight`.
  var highLatitudeRule: HighLatitudeRule?
  /// `-rounding nearest|up|none`. Switches to Custom.
  var rounding: Rounding?
  /// `-fajrAngle <degrees>`. Switches to Custom.
  var fajrAngle: Double?
  /// `-ishaAngle <degrees>`. Switches to Custom.
  var ishaAngle: Double?
  /// `-ramadanIsha on|off`: Isha 120 minutes after Maghrib in Ramadan, for an interval Isha.
  var ramadanIsha: Bool?
  /// `-alerts on|off`: alerts at the five prayers.
  var alerts: Bool?
  /// `-alertReminder <minutes>`: a reminder before each prayer, one of Settings' choices; `0`
  /// turns it off.
  var alertReminder: Int?
  /// `-alertFixtureIn <seconds>`: plan alerts from a fixture timetable whose five prayers start
  /// this long after launch, a minute apart (`AlertFixture`). This run only.
  var alertFixtureIn: TimeInterval?
  /// `-alertFixtureDay YYYY-MM-DD`: the day that owns the fixture's prayers. This run only.
  var alertFixtureDay: CivilDay?
  /// `-failAlertAdds dhuhr,asr`: adding these prayers' requests fails, to show a scheduling
  /// failure. This run only.
  var failAlertAdds: Set<PrayerKind> = []
  /// `-probeNotificationLimit <count>`: after planning, add this many temporary requests, count
  /// how many the system keeps, and remove them. This run only.
  var probeNotificationLimit: Int?

  init() {}

  init(arguments: [String]) {
    func value(after flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    func number(after flag: String) -> Double? {
      value(after: flag).flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
    }

    now = value(after: "-now").flatMap { try? Date($0, strategy: .iso8601) }
    frozen = arguments.contains("-frozen")
    language = value(after: "-language")
    resetSettings = arguments.contains("-resetSettings")

    if let id = value(after: "-place") {
      place = Place.preset(id)
    }
    if let latitude = number(after: "-latitude"), let longitude = number(after: "-longitude"),
      let zone = value(after: "-timeZone").flatMap(TimeZone.init(identifier:))
    {
      place = Place(
        id: Place.customID,
        location: PrayerLocation(
          latitude: latitude, longitude: longitude, timeZone: zone,
          countryCode: value(after: "-countryCode"), name: value(after: "-placeName")))
    }

    method = value(after: "-method").flatMap(MethodChoice.init(rawValue:))
    madhab = value(after: "-madhab").flatMap(Madhab.init(rawValue:))
    highLatitudeRule = value(after: "-highLatitudeRule").flatMap(HighLatitudeRule.init(rawValue:))
    rounding = value(after: "-rounding").flatMap(Rounding.init(rawValue:))
    fajrAngle = number(after: "-fajrAngle")
    ishaAngle = number(after: "-ishaAngle")
    switch value(after: "-ramadanIsha") {
    case "on": ramadanIsha = true
    case "off": ramadanIsha = false
    default: ramadanIsha = nil
    }
    switch value(after: "-alerts") {
    case "on": alerts = true
    case "off": alerts = false
    default: alerts = nil
    }
    alertReminder = value(after: "-alertReminder").flatMap(Int.init).flatMap { minutes in
      minutes == 0 || PhoneAlertOptions.reminderChoices.contains(minutes) ? minutes : nil
    }
    alertFixtureIn = number(after: "-alertFixtureIn").flatMap { $0 >= 0 ? $0 : nil }
    alertFixtureDay = value(after: "-alertFixtureDay").flatMap(CivilDay.init).flatMap {
      $0.isValid ? $0 : nil
    }
    failAlertAdds = Set(
      (value(after: "-failAlertAdds") ?? "").split(separator: ",").compactMap {
        PrayerKind(rawValue: String($0))
      })
    probeNotificationLimit = value(after: "-probeNotificationLimit").flatMap(Int.init).flatMap {
      (1...500).contains($0) ? $0 : nil
    }
  }

  /// Applies the place and calculation arguments: the method first, then the parameters that
  /// change it.
  func apply(to settings: inout AppSettings) {
    if let place {
      settings.place = place
    }
    if let method {
      settings.choose(method)
    }
    if let madhab {
      settings.calculation.parameters.madhab = madhab
    }
    if let highLatitudeRule {
      settings.calculation.parameters.highLatitudeRule = highLatitudeRule
    }
    if let ramadanIsha {
      settings.calculation.parameters.ramadanIsha = ramadanIsha ? AppSettings.ramadanRule : .off
    }
    if let rounding {
      settings.customize { $0.rounding = rounding }
    }
    if let fajrAngle {
      settings.customize { $0.fajr = .angle(fajrAngle) }
    }
    if let alerts {
      settings.alerts.isOn = alerts
    }
    if let alertReminder {
      settings.alerts.reminderMinutes = alertReminder == 0 ? nil : alertReminder
    }
    if let ishaAngle {
      settings.customize { $0.isha = .angle(ishaAngle) }
    }
  }
}

extension AppSettings {
  /// The Ramadan rule the app offers: Umm al-Qura's 120 minutes, on the calendar's own days.
  nonisolated static let ramadanRule = RamadanIshaRule.interval(minutes: 120, hijriDayOffset: 0)
}

/// The app's clock: the real clock, or one started at a chosen instant.
nonisolated struct AppClock: Sendable {
  /// The instant the app shows when it launches; `nil` uses the real clock.
  var start: Date?
  /// The real instant the app launched.
  var launch: Date
  /// Whether the clock stays at `start`. Only a clock with a start can be frozen.
  var frozen: Bool

  init(start: Date? = nil, launch: Date = Date(), frozen: Bool = false) {
    self.start = start
    self.launch = launch
    self.frozen = frozen && start != nil
  }

  /// The app's instant at a real instant.
  func now(at real: Date) -> Date {
    guard let start else { return real }
    return frozen ? start : start.addingTimeInterval(real.timeIntervalSince(launch))
  }
}
