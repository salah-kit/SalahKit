import Foundation
import SalahCore
import Testing

@testable import MenuBar

/// The menu bar's title and its refresh at the dates of a `.steps` plan.
@Suite("Display")
@MainActor
struct DisplayTests {
  let strings = MenuBarStrings(language: .english)
  let zone = Place.makkah.location.timeZone

  func title(at date: Date, settings: MenuBarSettings = Fixture.makkah) -> MenuBarTitle {
    let schedule = settings.schedule
    let state = schedule.state(at: date, through: date.addingTimeInterval(2 * 86_400))
    return MenuBarDisplay.title(
      for: state, at: date, strings: MenuBarStrings(language: settings.language),
      timeZone: settings.place.location.timeZone)
  }

  @Test("far from a prayer, the title names the next prayer and its time")
  func farFromAPrayer() throws {
    let asr = try Fixture.event(.asr)
    let date = asr.time.addingTimeInterval(-2 * 3_600)
    let time = strings.time(asr.time, in: zone)
    #expect(
      title(at: date) == MenuBarTitle(text: "Asr \(time)", accessibilityLabel: "Asr at \(time)"))
  }

  @Test("within an hour of a prayer, the title counts down, rounded down")
  func withinAnHour() throws {
    let asr = try Fixture.event(.asr)
    #expect(title(at: asr.time.addingTimeInterval(-27 * 60)).text == "Asr 27m")
    #expect(title(at: asr.time.addingTimeInterval(-27 * 60 + 1)).text == "Asr 26m")
    #expect(title(at: asr.time.addingTimeInterval(-45)).text == "Asr 45s")
    #expect(title(at: asr.time.addingTimeInterval(-3_600)).text == "Asr 1:00")
    #expect(
      title(at: asr.time.addingTimeInterval(-27 * 60)).accessibilityLabel == "Asr in 27 minutes")
  }

  @Test("just after a prayer starts, the title counts up")
  func justStarted() throws {
    let asr = try Fixture.event(.asr)
    #expect(title(at: asr.time).text == "Asr +0s")
    #expect(title(at: asr.time.addingTimeInterval(5 * 60)).text == "Asr +5m")
    #expect(
      title(at: asr.time.addingTimeInterval(5 * 60)).accessibilityLabel
        == "Asr started 5 minutes ago")
    // StatePolicy's default: until the iqama, or 15 minutes without one. Then the next prayer.
    let maghrib = try Fixture.event(.maghrib)
    let after = title(at: asr.time.addingTimeInterval(15 * 60))
    #expect(after.text.hasPrefix("Maghrib "))
    #expect(after.text.contains(strings.time(maghrib.time, in: zone)))
  }

  @Test("after Fajr's count-up the title follows sunrise, without counting sunrise up")
  func sunriseFocus() throws {
    let sunrise = try Fixture.event(.sunrise)
    #expect(title(at: sunrise.time.addingTimeInterval(-27 * 60)).text == "Sunrise 27m")
    #expect(title(at: sunrise.time).text.hasPrefix("Dhuhr "))
  }

  @Test("in Arabic, the title has Arabic names and digits")
  func arabic() throws {
    var settings = Fixture.makkah
    settings.language = .arabic
    let asr = try Fixture.event(.asr)
    let text = title(at: asr.time.addingTimeInterval(-27 * 60), settings: settings).text
    #expect(text.hasPrefix("العصر"))
    #expect(text.contains("٢٧"))
  }

  @Test("with no usable state, the title says the times aren't known")
  func unavailable() throws {
    // Tromsø around midsummer: the Sun doesn't set, so a calculation can't produce Maghrib, Isha
    // or Fajr, and the state is unavailable for part of the day.
    let settings = MenuBarSettings(place: .tromso, method: .muslimWorldLeague, language: .english)
    let schedule = settings.schedule
    let start = CivilDay(year: 2026, month: 6, day: 21).start(in: Place.tromso.location.timeZone)
    let moments = (0..<48).map { start.addingTimeInterval(Double($0) * 1_800) }
    let date = try #require(
      moments.first {
        if case .unavailable = schedule.state(at: $0, through: $0.addingTimeInterval(2 * 86_400)) {
          return true
        }
        return false
      })
    #expect(title(at: date, settings: settings).text == "No times")
  }

  @Test("the display refreshes every minute near a prayer and every 15 minutes elsewhere")
  func stepsRefresh() throws {
    let dhuhr = try Fixture.event(.dhuhr)
    let asr = try Fixture.event(.asr)
    // Past Dhuhr's hour, so the first refreshes are on the 15-minute grid.
    let start = dhuhr.time.addingTimeInterval(3_600 + 60)
    let clock = ManualClock(start)
    let display = DisplayModel(settings: Fixture.makkah, clock: clock)
    var shown: [(date: Date, text: String)] = []
    for _ in 0..<400 {
      guard let content = display.content else { break }
      shown.append((clock.now, content.title.text))
      guard clock.now < asr.time.addingTimeInterval(3_600) else { break }
      clock.fire()
    }
    let coarse = shown.filter { $0.date < asr.time.addingTimeInterval(-3_600) }
    let near = shown.filter {
      $0.date >= asr.time.addingTimeInterval(-3_600)
        && $0.date <= asr.time.addingTimeInterval(3_600)
    }
    // Far from the prayer: a refresh every 15 minutes, and the title names Asr's time.
    #expect(coarse.count >= 2)
    for pair in zip(coarse, coarse.dropFirst()) {
      #expect(pair.1.date.timeIntervalSince(pair.0.date) == 15 * 60)
    }
    #expect(coarse.allSatisfy { $0.text == "Asr \(strings.time(asr.time, in: zone))" })
    // Within an hour: a refresh every minute, on Asr's minutes, counting down, then up.
    #expect(near.count == 121)
    for pair in zip(near, near.dropFirst()) {
      #expect(pair.1.date.timeIntervalSince(pair.0.date) == 60)
    }
    #expect(near.first?.text == "Asr 1:00")
    #expect(near.contains { $0.date == asr.time && $0.text == "Asr +0s" })
    #expect(near.contains { $0.date == asr.time.addingTimeInterval(300) && $0.text == "Asr +5m" })
    // Each minute's title is exact at its refresh: the time left at that moment.
    for refresh in near where refresh.date < asr.time && refresh.text != "Asr 1:00" {
      let minutes = Int(asr.time.timeIntervalSince(refresh.date) / 60)
      #expect(refresh.text == "Asr \(minutes)m")
    }
  }

  @Test("the listed day changes at midnight in the place's zone, without a state change")
  func midnight() throws {
    let midnight = Fixture.day.adding(days: 1).start(in: zone)
    let clock = ManualClock(midnight.addingTimeInterval(-90))
    let display = DisplayModel(settings: Fixture.makkah, clock: clock)
    #expect(display.content?.day.day?.day == Fixture.day)
    #expect(clock.wakeDate.map { $0 <= midnight } == true)
    clock.advance(to: midnight)
    #expect(display.content?.day.day?.day == Fixture.day.adding(days: 1))
  }

  @Test("after a jump in time, a replan shows the new moment at once")
  func replanAfterAJump() throws {
    let asr = try Fixture.event(.asr)
    let clock = ManualClock(asr.time.addingTimeInterval(-3 * 3_600))
    let display = DisplayModel(settings: Fixture.makkah, clock: clock)
    let armed = try #require(clock.wakeDate)
    // The Mac slept until 27 minutes before Asr; the wake-up armed before hasn't run.
    clock.jump(to: asr.time.addingTimeInterval(-27 * 60 - 20))
    display.refresh(replanning: true)
    #expect(display.content?.title.text == "Asr 27m")
    #expect(display.content?.date == clock.now)
    #expect(clock.wakeDate.map { $0 > clock.now && $0 != armed } == true)
  }

  @Test("new settings show at once")
  func newSettings() throws {
    let asr = try Fixture.event(.asr)
    let clock = ManualClock(asr.time.addingTimeInterval(-27 * 60))
    let display = DisplayModel(settings: Fixture.makkah, clock: clock)
    var arabic = Fixture.makkah
    arabic.language = .arabic
    display.update(settings: arabic)
    #expect(display.content?.title.text.hasPrefix("العصر") == true)
  }

  @Test("in Arabic, the count-up's label agrees with the prayer's name")
  func arabicCountUpLabel() throws {
    var settings = Fixture.makkah
    settings.language = .arabic
    let asr = try Fixture.event(.asr)
    let label = title(at: asr.time.addingTimeInterval(5 * 60), settings: settings)
      .accessibilityLabel
    // The prayer names are masculine, so the verb is بدأ وقت, not بدأت.
    #expect(Self.plain(label).hasPrefix("بدأ وقت العصر منذ"), "\(label)")
  }

  @Test("counts agree with their nouns, in English and in Arabic")
  func countsAgree() {
    let english = MenuBarStrings(language: .english)
    #expect(english("\(1) notifications confirmed.") == "1 notification confirmed.")
    #expect(english("\(3) notifications confirmed.") == "3 notifications confirmed.")
    #expect(
      english("\(1) notifications confirmed until \("Friday").")
        == "1 notification confirmed until Friday.")
    #expect(
      english("Following \(1) alerts while the app runs.")
        == "Following 1 alert while the app runs.")
    #expect(
      english("Following \(20) alerts while the app runs.")
        == "Following 20 alerts while the app runs.")

    let arabic = MenuBarStrings(language: .arabic)
    let confirmed = [
      1: "تأكّد إشعار واحد.", 2: "تأكّد إشعاران.", 5: "تأكّد 5 إشعارات.", 11: "تأكّد 11 إشعارًا.",
    ]
    for (count, text) in confirmed {
      #expect(Self.plain(arabic("\(count) notifications confirmed.")) == text)
    }
    #expect(
      Self.plain(arabic("\(3) notifications confirmed until \("الجمعة")."))
        == "تأكّد 3 إشعارات حتى الجمعة.")
    #expect(
      Self.plain(arabic("Following \(1) alerts while the app runs."))
        == "يتابع التطبيق تنبيهًا واحدًا ما دام يعمل.")
    #expect(
      Self.plain(arabic("Following \(20) alerts while the app runs."))
        == "يتابع التطبيق 20 تنبيهًا ما دام يعمل.")
    // The reminder picker's choices.
    let before = [
      5: "قبلها بـ 5 دقائق", 10: "قبلها بـ 10 دقائق", 15: "قبلها بـ 15 دقيقة",
      30: "قبلها بـ 30 دقيقة",
    ]
    for (minutes, text) in before {
      #expect(Self.plain(arabic("\(minutes) minutes before")) == text)
    }
  }

  /// The text without bidi isolates, and with Western digits, so it compares whatever digits and
  /// isolates the locale's formatting adds.
  static func plain(_ text: String) -> String {
    let arabicIndic = Array("٠١٢٣٤٥٦٧٨٩")
    return String(
      text.unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }.map { scalar in
        arabicIndic.firstIndex(of: Character(scalar)).map { Character(String($0)) }
          ?? Character(scalar)
      })
  }
}
