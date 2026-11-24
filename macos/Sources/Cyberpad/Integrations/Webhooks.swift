import Foundation

/// `webhook.call`: een HTTP-verzoek naar IFTTT, Zapier, n8n, Home Assistant-webhooks of een eigen script.
/// Een webhook staat in de layout (`url`) of met naam in integrations.json (dan kan een geheime header uit de sleutelhanger).
final class WebhookRunner {
    var hooks: [String: IntegrationConfig.Webhook] = [:]
    var secret: (String) -> String? = { _ in nil }
    var onError: ((String) -> Void)?
    private let session: URLSession

    static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
    }

    func call(_ a: ActionSpec, onFail: (() -> Void)?) throws {
        var url = a.url, method = a.method, headers = a.headers ?? [:], body = a.body, timeout = 10
        if let name = a.webhook {
            guard let h = hooks[name] else {
                throw ActionRunner.ActionError.failed(L("Webhook “{0}” staat niet in integrations.json", name))
            }
            url = h.url
            method = a.method ?? h.method
            headers = (h.headers ?? [:]).merging(a.headers ?? [:]) { $1 }
            body = a.body ?? h.body
            timeout = h.timeout ?? 10
            if let header = h.secretHeader {
                guard let value = secret(Integrations.webhookAccount(name)) else {
                    throw ActionRunner.ActionError.failed(L("Geheim voor webhook “{0}” ontbreekt (menubalk › Koppelingen…)", name))
                }
                headers[header] = value
            }
        }
        guard let s = url, let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
              let host = u.host, !host.isEmpty else {
            throw ActionRunner.ActionError.missing(L("geldige http(s)-url voor de webhook"))
        }
        let m = (method ?? (body == nil ? "GET" : "POST")).uppercased()
        guard Self.methods.contains(m) else { throw ActionRunner.ActionError.failed(L("Onbekende methode: {0}", m)) }

        var req = URLRequest(url: u, timeoutInterval: TimeInterval(min(max(timeout, 1), 60)))
        req.httpMethod = m
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if req.value(forHTTPHeaderField: "User-Agent") == nil { req.setValue("Cyberpad", forHTTPHeaderField: "User-Agent") }
        if let body, m != "GET" {
            req.httpBody = Data(body.utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                let isJSON = (try? JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed])) != nil
                req.setValue(isJSON ? "application/json" : "text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }
        let label = a.webhook.map { "“\($0)”" } ?? host
        session.dataTask(with: req) { [weak self] _, resp, err in
            DispatchQueue.main.async {
                if let err {
                    onFail?()
                    self?.onError?(L("Webhook {0} mislukt: {1}", label, err.localizedDescription))
                } else if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
                    onFail?()
                    self?.onError?("Webhook \(label) gaf foutcode \(code)")
                }
            }
        }.resume()
    }
}
