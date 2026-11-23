import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // geen Dock-icoon, ook niet bij `swift run`
        signal(SIGPIPE, SIG_IGN) // een gestopte plugin mag Cyberpad niet laten crashen
        Core.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { Core.shared.handle(url: u) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Core.shared.plugins.stopAll()
    }
}

@main
struct CyberpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var core = Core.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(core)
        } label: {
            Image(systemName: "square.grid.3x3.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @EnvironmentObject var core: Core

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            pairingSection
            Divider()
            devicesSection
            Divider()
            statusSection
            if !core.plugins.plugins.isEmpty || !core.plugins.problems.isEmpty { Divider(); pluginsSection }
            if !core.hasAccessibility || core.layoutError != nil { Divider(); warnings }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("CYBERPAD").font(.system(.headline, design: .monospaced)).kerning(2)
            Spacer()
            Circle().fill(core.serverError == nil ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(core.serverError == nil ? "Actief op :\(Server.port)" : "Gestopt")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = core.serverError { Text(err).font(.caption).foregroundStyle(.red) }
            Text("Open op je tablet:").font(.caption).foregroundStyle(.secondary)
            Text(Core.hostURL).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            if let direct = core.directURL {
                Text("of \(direct)").font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack(alignment: .center, spacing: 14) {
                if let qr = qrImage(core.directURL ?? Core.hostURL) {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 96, height: 96)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Koppelcode").font(.caption).foregroundStyle(.secondary)
                    Text(spaced(core.pairing.code))
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(core.pairing.codeExpires.timeIntervalSince(ctx.date)))
                        Text("Nieuwe code over \(left / 60):\(String(format: "%02d", left % 60))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Nieuwe code") { core.pairing.rotate() }.controlSize(.small)
                }
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gekoppelde tablets").font(.caption).foregroundStyle(.secondary)
            if core.pairing.devices.isEmpty {
                Text("Nog geen tablets gekoppeld").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(core.pairing.devices) { d in
                HStack {
                    Circle().fill(core.online.contains(d.id) ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name)
                        if let seen = d.lastSeen {
                            Text("Laatst gezien \(seen.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !core.context.profiles.isEmpty {
                        Menu(core.context.profiles.first { $0.id == d.profile }?.name ?? "Automatisch") {
                            Button("Automatisch") { core.pairing.setProfile(id: d.id, profile: nil) }
                            Divider()
                            ForEach(core.context.profiles, id: \.id) { p in
                                Button(p.name) { core.pairing.setProfile(id: d.id, profile: p.id) }
                            }
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                    Button("Intrekken", role: .destructive) { core.pairing.revoke(id: d.id) }.controlSize(.small)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: core.meetingInfo == nil ? "video.slash" : "video.fill")
                    .foregroundStyle(core.meetingInfo == nil ? Color.secondary : Color.green)
                if let m = core.meetingInfo {
                    Text("In vergadering: \(m.name)")
                    if let muted = m.muted {
                        Text(muted ? "· mic uit" : "· mic aan").foregroundStyle(muted ? .red : .secondary)
                        if m.statusSource == "estimated" { Text("(geschat)").font(.caption2).foregroundStyle(.secondary) }
                    }
                } else {
                    Text("Geen vergadering").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                switch core.agendaAccess {
                case .granted: Text("Agenda gekoppeld").foregroundStyle(.secondary)
                case .notDetermined:
                    Text("Agenda niet gekoppeld").foregroundStyle(.secondary)
                    Button("Toestaan…") { core.requestAgendaAccess() }.controlSize(.small)
                case .denied:
                    Text("Geen toegang tot Agenda").foregroundStyle(.orange)
                    Button("Instellingen…") { core.requestAgendaAccess() }.controlSize(.small)
                }
            }
            .font(.callout)
            profileRow
            integrationRow("house", "Home Assistant", core.integrations.ha.status)
            integrationRow("antenna.radiowaves.left.and.right", "MQTT", core.integrations.mqtt.status)
            if let e = core.integrations.configError { Text(e).font(.caption).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder
    private var profileRow: some View {
        if !core.context.profiles.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack").foregroundStyle(.secondary)
                Picker("Profiel", selection: Binding(get: { core.context.override ?? "auto" },
                                                     set: { core.context.setOverride($0) })) {
                    Text("Automatisch (\(core.context.autoProfile?.name ?? "—"))").tag("auto")
                    ForEach(core.context.profiles, id: \.id) { p in Text(p.name).tag(p.id) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            .font(.callout)
        }
        if let a = core.context.frontApp {
            HStack(spacing: 6) {
                Image(systemName: "macwindow").foregroundStyle(.secondary)
                Text(a.name).lineLimit(1)
                if let page = core.context.contextPage,
                   let name = core.layouts.layout.pages.first(where: { $0.id == page })?.name {
                    Text("→ pagina \(name)").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func integrationRow(_ icon: String, _ name: String, _ st: LinkStatus) -> some View {
        if st != .off {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(st == .connected ? Color.green : Color.secondary)
                Text("\(name): \(st == .connected ? "verbonden" : st.text)")
                    .foregroundStyle(st.code == "error" ? Color.orange : Color.secondary)
                    .lineLimit(2)
            }
            .font(.callout)
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plugins").font(.caption).foregroundStyle(.secondary)
            ForEach(core.plugins.sorted, id: \.manifest.id) { p in
                HStack(spacing: 6) {
                    Text(p.manifest.icon ?? "🧩")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.manifest.name + (p.manifest.version.map { " \($0)" } ?? ""))
                        Text(p.status.text).font(.caption2)
                            .foregroundStyle(statusColor(p.status))
                            .lineLimit(2)
                    }
                    Spacer()
                    if core.plugins.isApproved(p.manifest.id) && p.status != .changed {
                        Button("Uitzetten") { core.plugins.revoke(p.manifest.id) }.controlSize(.small)
                    } else {
                        Button(p.status == .changed ? "Opnieuw toestaan…" : "Aanzetten…") { core.approvePlugin(p.manifest.id) }
                            .controlSize(.small)
                    }
                }
                .font(.callout)
            }
            ForEach(core.plugins.problems, id: \.self) { e in
                Text(e).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private func statusColor(_ s: PluginManager.Status) -> Color {
        switch s {
        case .running: return .green
        case .changed: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !core.hasAccessibility {
                Text("Media- en toetsacties hebben Toegankelijkheid nodig.").font(.caption)
                Button("Toegankelijkheid toestaan…") { core.requestAccessibility() }.controlSize(.small)
            }
            if let e = core.layoutError { Text(e).font(.caption).foregroundStyle(.orange) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Layout bewerken") { core.openLayoutFile() }
                Button("Koppelingen…") { core.openIntegrations() }
                Button("Map") { core.openSupportFolder() }
                Button("Plugins") { core.openPluginFolder() }
                Spacer()
                Button("Stop") { NSApp.terminate(nil) }
            }
            Button("Standaard-layout terugzetten…") { core.resetLayout() }
        }
        .controlSize(.small)
    }

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private func qrImage(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
