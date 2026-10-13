import SalahCore
import SalahTimes

nonisolated extension CalculationMethod {
  /// SalahTimes' suggested method for the location's country, or `nil` when the location has
  /// no country code or SalahTimes has no sourced suggestion for it.
  ///
  /// A suggestion is a starting point, not a ruling: mosques and communities in one country
  /// often follow different methods, so let your users change it. Nothing in SalahKit applies
  /// a suggestion on its own. SalahTimes' `METHODS.md` gives the source of every entry.
  ///
  /// ```swift
  /// let method = CalculationMethod.suggested(for: location) ?? .muslimWorldLeague
  /// ```
  ///
  /// - Parameter location: A location whose ``SalahCore/PrayerLocation/countryCode`` is an
  ///   ISO 3166-1 alpha-2 code, in either case.
  /// - Returns: The suggested method, or `nil`.
  public static func suggested(for location: PrayerLocation) -> CalculationMethod? {
    guard let code = location.countryCode else { return nil }
    return suggested(forCountryCode: code)
  }
}
