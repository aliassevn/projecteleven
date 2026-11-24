import SwiftUI
import AppKit

/// Venster "Koppelingen": adressen in integrations.json, tokens en wachtwoorden in de sleutelhanger.
final class IntegrationsWindow {
    static let shared = IntegrationsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = L("Cyberpad — Koppelingen")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: IntegrationsView().environmentObject(Core.shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct IntegrationsView: View {
    @EnvironmentObject var core: Core

    @State private var haURL = ""
    @State private var haToken = ""
    @State private var haHasToken = false
    @State private var mqttHost = ""
    @State private var mqttPort = ""
    @State private var mqttTLS = false
    @State private var mqttUser = ""
    @State private var mqttPassword = ""
    @State private var mqttHasPassword = false
    @State private var hookSecrets: [String: String] = [:]
    @State private var hookHasSecret: Set<String> = []
    @State private var clear: Set<String> = []
    @State private var message: String?
    @State private var messageIsError = false

    private var i: Integrations { core.integrations }
    private var secretHooks: [String] {
        (i.config.webhooks ?? [:]).filter { $0.value.secretHeader != nil }.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(L("Adres"), text: $haURL, prompt: Text("http://homeassistant.local:8123"))
                    SecureField("Token", text: $haToken,
                                prompt: Text(haHasToken && !clear.contains(Integrations.haTokenAccount) ? L("bewaard in sleutelhanger") : "long-lived access token"))
                    if haHasToken {
                        Toggle(L("Bewaard token wissen"), isOn: binding(Integrations.haTokenAccount))
                    }
                    status(i.ha.status)
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text(L("Maak een token in Home Assistant via Profiel › Beveiliging › Long-lived access tokens. HomeKit-apparaten bedien je via de HomeKit-koppeling van Home Assistant."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    TextField(L("Server"), text: $mqttHost, prompt: Text(L("mqtt.local of 192.168.1.10")))
                    TextField(L("Poort"), text: $mqttPort, prompt: Text(mqttTLS ? "8883" : "1883"))
                    Toggle(L("Versleuteld (TLS)"), isOn: $mqttTLS)
                    TextField(L("Gebruiker"), text: $mqttUser, prompt: Text(L("optioneel")))
                    SecureField(L("Wachtwoord"), text: $mqttPassword,
                                prompt: Text(mqttHasPassword && !clear.contains(Integrations.mqttPasswordAccount) ? L("bewaard in sleutelhanger") : L("optioneel")))
                    if mqttHasPassword {
                        Toggle(L("Bewaard wachtwoord wissen"), isOn: binding(Integrations.mqttPasswordAccount))
                    }
                    status(i.mqtt.status)
                } header: {
                    Text("MQTT")
                }

                Section {
                    if secretHooks.isEmpty {
                        Text(L("Webhooks met een naam zet je in integrations.json. Geef er een `secretHeader` aan, dan vul je het geheim hier in."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(secretHooks, id: \.self) { name in
                        let account = Integrations.webhookAccount(name)
                        SecureField(name, text: Binding(get: { hookSecrets[name] ?? "" }, set: { hookSecrets[name] = $0 }),
                                    prompt: Text(hookHasSecret.contains(name) && !clear.contains(account) ? L("bewaard in sleutelhanger") : L("geheim")))
                    }
                    Button(L("integrations.json openen")) { openConfigFile() }
                } header: {
                    Text("Webhooks")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let message {
                    Text(message).font(.callout).foregroundStyle(messageIsError ? Color.red : Color.secondary)
                }
                Spacer()
                Button(L("Opslaan")) { save() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 440, minHeight: 480)
        .onAppear(perform: load)
    }

    private func binding(_ account: String) -> Binding<Bool> {
        Binding(get: { clear.contains(account) },
                set: { if $0 { clear.insert(account) } else { clear.remove(account) } })
    }

    @ViewBuilder
    private func status(_ st: LinkStatus) -> some View {
        if st != .off {
            HStack(spacing: 6) {
                Circle().fill(st == .connected ? Color.green : st == .connecting ? Color.yellow : Color.orange)
                    .frame(width: 8, height: 8)
                Text(st.text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func load() {
        let c = i.config
        haURL = c.homeAssistant?.url ?? ""
        haHasToken = i.hasSecret(Integrations.haTokenAccount)
        mqttHost = c.mqtt?.host ?? ""
        mqttPort = c.mqtt?.port.map(String.init) ?? ""
        mqttTLS = c.mqtt?.tls ?? false
        mqttUser = c.mqtt?.username ?? ""
        mqttHasPassword = i.hasSecret(Integrations.mqttPasswordAccount)
        hookHasSecret = Set(secretHooks.filter { i.hasSecret(Integrations.webhookAccount($0)) })
        haToken = ""; mqttPassword = ""; hookSecrets = [:]; clear = []
    }

    private func save() {
        var c = i.config
        let url = haURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            c.homeAssistant = nil
        } else {
            guard HomeAssistantClient.normalize(url) != nil else { show(L("Ongeldig Home Assistant-adres"), error: true); return }
            c.homeAssistant = .init(url: url)
        }
        let host = mqttHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            c.mqtt = nil
        } else {
            var port: Int?
            if !mqttPort.isEmpty {
                guard let p = Int(mqttPort), (1...65535).contains(p) else { show(L("Ongeldige MQTT-poort"), error: true); return }
                port = p
            }
            let user = mqttUser.trimmingCharacters(in: .whitespaces)
            c.mqtt = .init(host: host, port: port, tls: mqttTLS ? true : nil,
                           username: user.isEmpty ? nil : user, clientId: c.mqtt?.clientId)
        }
        var secrets: [String: String] = [Integrations.haTokenAccount: haToken.trimmingCharacters(in: .whitespacesAndNewlines),
                                         Integrations.mqttPasswordAccount: mqttPassword]
        for (name, v) in hookSecrets { secrets[Integrations.webhookAccount(name)] = v }
        if let err = i.save(c, secrets: secrets, clear: clear) {
            show(err, error: true)
        } else {
            load()
            show(L("Opgeslagen"), error: false)
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }

    private func openConfigFile() {
        let url = i.url
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = i.save(i.config, secrets: [:], clear: [])
        }
        NSWorkspace.shared.open(url)
    }
}
