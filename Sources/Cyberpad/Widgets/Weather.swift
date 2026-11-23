import Foundation

/// Weer via Open-Meteo (gratis, geen API-sleutel). Alleen de plaatsnaam of coördinaten uit de layout gaan naar buiten.
final class WeatherService {
    struct Place: Equatable { var name: String; var lat: Double; var lon: Double }

    private var places: [String: Place] = [:]       // plaatsnaam → coördinaten (cache)
    private var data: [String: [String: Any]] = [:]  // sleutel per locatie
    private var fetchedAt: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": "Cyberpad/0.1"]
        return URLSession(configuration: c)
    }()
    var onUpdate: (() -> Void)?

    static let refreshInterval: TimeInterval = 15 * 60

    private func key(_ cfg: WidgetConfig?) -> String {
        if let lat = cfg?.lat, let lon = cfg?.lon { return String(format: "%.3f,%.3f", lat, lon) }
        return (cfg?.city ?? "Amsterdam").lowercased()
    }

    func json(for cfg: WidgetConfig?) -> [String: Any] {
        data[key(cfg)] ?? ["status": "loading"]
    }

    /// Haalt nieuwe gegevens op als ze ouder zijn dan 15 minuten.
    func refresh(_ cfg: WidgetConfig?) {
        let k = key(cfg)
        guard !inFlight.contains(k) else { return }
        if let t = fetchedAt[k], Date().timeIntervalSince(t) < Self.refreshInterval { return }
        inFlight.insert(k)

        resolve(cfg) { [weak self] place, error in
            guard let self else { return }
            guard let place else {
                self.finish(k, ["status": "error", "error": error ?? "Plaats niet gevonden"], retryIn: 300)
                return
            }
            self.fetchForecast(place) { result in self.finish(k, result, retryIn: result["status"] as? String == "ok" ? nil : 300) }
        }
    }

    private func finish(_ k: String, _ result: [String: Any], retryIn: TimeInterval?) {
        DispatchQueue.main.async {
            self.inFlight.remove(k)
            self.data[k] = result
            // Bij een fout over 5 minuten opnieuw proberen in plaats van na 15.
            self.fetchedAt[k] = retryIn.map { Date().addingTimeInterval($0 - Self.refreshInterval) } ?? Date()
            self.onUpdate?()
        }
    }

    private func resolve(_ cfg: WidgetConfig?, done: @escaping (Place?, String?) -> Void) {
        if let lat = cfg?.lat, let lon = cfg?.lon {
            done(Place(name: cfg?.city ?? "", lat: lat, lon: lon), nil); return
        }
        let city = cfg?.city ?? "Amsterdam"
        if let p = places[city.lowercased()] { done(p, nil); return }

        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "nl")]
        session.dataTask(with: c.url!) { [weak self] data, _, err in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (obj["results"] as? [[String: Any]])?.first,
                  let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
                done(nil, err == nil ? "Plaats “\(city)” niet gevonden" : "Geen internet")
                return
            }
            let p = Place(name: first["name"] as? String ?? city, lat: lat, lon: lon)
            DispatchQueue.main.async { self?.places[city.lowercased()] = p }
            done(p, nil)
        }.resume()
    }

    private func fetchForecast(_ p: Place, done: @escaping ([String: Any]) -> Void) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(p.lat)), .init(name: "longitude", value: String(p.lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day,wind_speed_10m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "1"),
        ]
        session.dataTask(with: c.url!) { data, _, err in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any],
                  let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue,
                  let code = (cur["weather_code"] as? NSNumber)?.intValue else {
                done(["status": "error", "error": err == nil ? "Onverwacht antwoord van Open-Meteo" : "Geen internet"])
                return
            }
            let daily = obj["daily"] as? [String: Any]
            func firstNum(_ k: String) -> Double? { ((daily?[k] as? [Any])?.first as? NSNumber)?.doubleValue }
            let isDay = ((cur["is_day"] as? NSNumber)?.intValue ?? 1) == 1
            let desc = Self.describe(code, day: isDay)
            var out: [String: Any] = [
                "status": "ok", "place": p.name, "temp": (temp * 10).rounded() / 10,
                "code": code, "desc": desc.text, "icon": desc.icon,
                "updated": Int(Date().timeIntervalSince1970 * 1000),
            ]
            if let v = firstNum("temperature_2m_max") { out["max"] = v.rounded() }
            if let v = firstNum("temperature_2m_min") { out["min"] = v.rounded() }
            if let v = firstNum("precipitation_probability_max") { out["rain"] = Int(v) }
            if let v = (cur["wind_speed_10m"] as? NSNumber)?.doubleValue { out["wind"] = Int(v.rounded()) }
            done(out)
        }.resume()
    }

    /// WMO-weercodes naar Nederlandse omschrijving en emoji.
    static func describe(_ code: Int, day: Bool) -> (text: String, icon: String) {
        switch code {
        case 0: return ("Onbewolkt", day ? "☀️" : "🌙")
        case 1: return ("Vrijwel onbewolkt", day ? "🌤" : "🌙")
        case 2: return ("Half bewolkt", day ? "⛅️" : "☁️")
        case 3: return ("Bewolkt", "☁️")
        case 45, 48: return ("Mist", "🌫")
        case 51, 53, 55: return ("Motregen", "🌦")
        case 56, 57: return ("IJzel", "🌧")
        case 61, 63: return ("Regen", "🌧")
        case 65: return ("Zware regen", "🌧")
        case 66, 67: return ("IJzel", "🌧")
        case 71, 73, 75, 77: return ("Sneeuw", "🌨")
        case 80, 81: return ("Buien", "🌦")
        case 82: return ("Zware buien", "⛈")
        case 85, 86: return ("Sneeuwbuien", "🌨")
        case 95, 96, 99: return ("Onweer", "⛈")
        default: return ("Onbekend", "🌡")
        }
    }
}
