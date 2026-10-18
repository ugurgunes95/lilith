import Foundation

// MARK: Unit conversion

/// Lowercased names and symbols, English and Turkish. A plural ending in "s" falls back to its singular.
let unitAliases: [String: Dimension] = {
    var a: [String: Dimension] = [:]
    func add(_ unit: Dimension, _ names: String) { for n in names.split(separator: " ") { a[String(n)] = unit } }
    add(UnitLength.kilometers, "km kilometer kilometre")
    add(UnitLength.meters, "m meter metre")
    add(UnitLength.centimeters, "cm centimeter santimetre")
    add(UnitLength.millimeters, "mm millimeter milimetre")
    add(UnitLength.miles, "mi mile mil")
    add(UnitLength.yards, "yd yard yarda")
    add(UnitLength.feet, "ft feet foot fit")
    add(UnitLength.inches, "in inch inches inç")
    add(UnitMass.metricTons, "t ton tonne")
    add(UnitMass.kilograms, "kg kilogram kilo")
    add(UnitMass.grams, "g gram")
    add(UnitMass.pounds, "lb lbs pound libre")
    add(UnitMass.ounces, "oz ounce ons")
    add(UnitVolume.liters, "l lt liter litre")
    add(UnitVolume.milliliters, "ml milliliter mililitre")
    add(UnitVolume.gallons, "gal gallon galon")
    add(UnitTemperature.celsius, "c °c celsius santigrat")
    add(UnitTemperature.fahrenheit, "f °f fahrenheit fahrenhayt")
    add(UnitTemperature.kelvin, "kelvin")
    add(UnitSpeed.kilometersPerHour, "km/h kmh kph")
    add(UnitSpeed.milesPerHour, "mph")
    add(UnitSpeed.metersPerSecond, "m/s")
    add(UnitSpeed.knots, "kn knot")
    add(UnitArea.squareKilometers, "km2 km² kilometrekare")
    add(UnitArea.squareMeters, "m2 m² sqm metrekare")
    add(UnitArea.squareFeet, "ft2 ft² sqft")
    add(UnitArea.hectares, "ha hectare hektar")
    add(UnitArea.acres, "acre akre")
    add(UnitArea(symbol: "dönüm", converter: UnitConverterLinear(coefficient: 1000)), "dönüm donum")
    add(UnitDuration.hours, "h hr hour saat sa")
    add(UnitDuration.minutes, "min minute dakika dk")
    add(UnitDuration.seconds, "s sec second saniye sn")
    add(UnitInformationStorage.bytes, "b byte bayt")
    add(UnitInformationStorage.kilobytes, "kb")
    add(UnitInformationStorage.megabytes, "mb")
    add(UnitInformationStorage.gigabytes, "gb")
    add(UnitInformationStorage.terabytes, "tb")
    return a
}()

func unit(_ s: String) -> Dimension? {
    unitAliases[s] ?? (s.count > 3 && s.hasSuffix("s") ? unitAliases[String(s.dropLast())] : nil)
}

// MARK: Currency

let currencyAliases = ["$": "USD", "dolar": "USD", "dollar": "USD", "€": "EUR", "euro": "EUR", "avro": "EUR",
                       "£": "GBP", "sterlin": "GBP", "₺": "TRY", "tl": "TRY", "lira": "TRY", "¥": "JPY", "yen": "JPY"]
let localCurrency = Locale.current.currency?.identifier ?? "USD"

/// USD-based daily rates from open.er-api.com (free, no key; its terms require the attribution shown on results).
/// Kept in UserDefaults so conversions work offline. Refetched when the panel opens and the copy is over 12h old.
enum Rates {
    static var rates = UserDefaults.standard.dictionary(forKey: "rates") as? [String: Double] ?? [:]
    static var updated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "ratesUpdated"))  // provider's time
    static var fetched = UserDefaults.standard.object(forKey: "ratesFetched") as? Date ?? .distantPast
    static var lastTry = Date.distantPast
    static var onUpdate: () -> Void = {}

    static func refreshIfStale() {
        let now = Date()
        // 5 min between tries so opening the panel offline doesn't fire a request every time.
        guard UserDefaults.standard.bool(forKey: "convert"), now.timeIntervalSince(fetched) > 12 * 3600,
              now.timeIntervalSince(lastTry) > 300 else { return }
        lastTry = now
        URLSession.shared.dataTask(with: URL(string: "https://open.er-api.com/v6/latest/USD")!) { data, _, _ in
            struct Response: Decodable { let rates: [String: Double]; let timeLastUpdateUnix: Double }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let data, let r = try? decoder.decode(Response.self, from: data) else { return }
            DispatchQueue.main.async {
                (rates, updated, fetched) = (r.rates, Date(timeIntervalSince1970: r.timeLastUpdateUnix), Date())
                UserDefaults.standard.set(rates, forKey: "rates")
                UserDefaults.standard.set(r.timeLastUpdateUnix, forKey: "ratesUpdated")
                UserDefaults.standard.set(fetched, forKey: "ratesFetched")
                onUpdate()
            }
        }.resume()
    }
}

// MARK: Parsing

enum Conversion {
    case unit(Double, Dimension), money(Double, String)
    var value: Double { switch self { case let .unit(v, _), let .money(v, _): v } }
}

// [symbol] number [unit] [[to|in|into] target]: "10 km to mi", "5 kg lb", "$100", "€50 tl", "100 usd"
let conversionPattern = try! Regex(#"([$€£₺¥])?\s*(-?\d+(?:[.,]\d+)?)\s*([^\s\d.,+\-*/^()]\S*)?(?:\s+(?:(?:to|in|into)\s+)?(\S+))?"#)

/// Units need a target of the same kind. A currency without one goes to the local currency (or USD from it).
func convert(_ q: String, rates: [String: Double], local: String) -> Conversion? {
    guard let m = try? conversionPattern.wholeMatch(in: q.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
    let part = { (i: Int) in m.output[i].substring.map(String.init) }
    guard let v = part(2).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) else { return nil }
    var from = part(3), to = part(4)
    if let symbol = part(1) { (from, to) = (symbol, to ?? from) }  // "$100 tl": the word after the number is the target
    guard let from else { return nil }
    if let a = unit(from) {
        // Same kind of unit; compared by base unit because built-ins are private subclasses.
        guard let to, let b = unit(to), type(of: a).baseUnit() == type(of: b).baseUnit() else { return nil }
        return .unit(b.converter.value(fromBaseUnitValue: a.converter.baseUnitValue(fromValue: v)), b)
    }
    func code(_ s: String) -> String? { currencyAliases[s] ?? (rates[s.uppercased()] != nil ? s.uppercased() : nil) }
    guard let a = code(from) else { return nil }
    let b: String? = if let to { code(to) } else { a == local ? (local == "USD" ? "EUR" : "USD") : local }
    guard let b, let ra = rates[a], let rb = rates[b] else { return nil }
    return .money(v / ra * rb, b)
}

// MARK: Result row

func significant(grouped: Bool) -> NumberFormatter {
    let f = numberFormat(grouped: grouped)
    f.usesSignificantDigits = true
    f.maximumSignificantDigits = 6
    return f
}
let unitFormat: MeasurementFormatter = {
    let f = MeasurementFormatter()
    f.unitOptions = .providedUnit
    f.unitStyle = .medium
    f.numberFormatter = significant(grouped: true)
    return f
}()

func conversionItem(_ q: String) -> Item? {
    guard let c = convert(q, rates: Rates.rates, local: localCurrency) else { return nil }
    let shown: String, raw: String, source: String
    switch c {
    case let .unit(v, u):
        shown = unitFormat.string(from: Measurement(value: v, unit: u as Unit))
        raw = significant(grouped: false).string(from: v as NSNumber) ?? ""
        source = q
    case let .money(v, code):
        let money = NumberFormatter()
        money.numberStyle = .currency
        money.currencyCode = code
        let plain = numberFormat(grouped: false)  // copy without symbol or grouping, at the currency's precision
        plain.minimumFractionDigits = money.maximumFractionDigits
        plain.maximumFractionDigits = money.maximumFractionDigits
        shown = money.string(from: v as NSNumber) ?? ""
        raw = plain.string(from: v as NSNumber) ?? ""
        source = "\(q) · Rates By Exchange Rate API, \(Rates.updated.formatted(.dateTime.day().month()))"
    }
    return Item(title: shown, subtitle: "\(source) · Enter to copy", icon: { symbol("arrow.left.arrow.right.circle") }) { copy(raw) }
}
