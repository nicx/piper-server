import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ServerSettingsTab()
                .tabItem { Label("Dienst", systemImage: "waveform") }
            VoicesSettingsTab()
                .tabItem { Label("Stimmen", systemImage: "person.wave.2") }
            GeneralSettingsTab()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .frame(width: 520)
        .padding()
    }
}

// MARK: - Dienst

private struct ServerSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var server: ServerController

    var body: some View {
        Form {
            Section {
                TextField("Port", value: $settings.port, format: .number.grouping(.never))
                Picker("Erreichbar für", selection: $settings.bindAddress) {
                    Text("Nur diesen Mac (127.0.0.1)").tag(AppSettings.loopbackAddress)
                    Text("Alle Geräte im Netz (0.0.0.0)").tag(AppSettings.anyAddress)
                }
                Toggle("Dienst beim Start der App starten", isOn: $settings.startOnLaunch)
                Toggle("Bei Absturz automatisch neu starten", isOn: $settings.autoRestart)
                Toggle("Ausführliches Protokoll (--debug)", isOn: $settings.verbose)
            } footer: {
                Text("Standard ist Port \(String(AppSettings.defaultPort)) (Wyoming-Piper-Standard). „Nur diesen Mac“ genügt, wenn Home Assistant auf demselben Mac läuft. Der Dienst hat keine Authentifizierung.")
            }

            Section {
                HStack {
                    Text("Änderungen werden beim nächsten Start wirksam.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Übernehmen & neu starten") { server.restart() }
                        .disabled(!server.status.isActive)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Stimmen

private struct VoicesSettingsTab: View {
    @EnvironmentObject var app: AppEnvironment
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var voices: VoiceManager

    var body: some View {
        Form {
            Section {
                ForEach(VoiceCatalog.german) { voice in
                    row(voice)
                }
            } footer: {
                Text("Stimmen werden einmalig von huggingface.co/rhasspy/piper-voices geladen und laufen danach offline. Lizenz = Lizenz der Trainingsdaten laut Model Card.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ voice: Voice) -> some View {
        let _ = voices.revision
        let installed = voices.isInstalled(voice.id)
        let active = voice.id == settings.voice
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(voice.displayName) · \(voice.quality)").fontWeight(active ? .semibold : .regular)
                Text("\(voice.id) · \(voice.sizeMB) MB · \(voice.license)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if voices.downloading == voice {
                ProgressView(value: voices.progress).frame(width: 90)
            } else if active {
                Text("aktiv").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(installed ? "Verwenden" : "Laden & verwenden") { app.selectVoice(voice) }
                    .disabled(voices.downloading != nil)
                if installed {
                    Button("Löschen") { voices.remove(voice) }
                        .disabled(voices.downloading != nil)
                }
            }
        }
    }
}

// MARK: - Allgemein

private struct GeneralSettingsTab: View {
    @EnvironmentObject var app: AppEnvironment
    @EnvironmentObject var server: ServerController
    @EnvironmentObject var env: EnvironmentManager
    @EnvironmentObject var loginItem: LoginItemManager
    @State private var latest: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section("Start") {
                Toggle("Beim Anmelden starten", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if let err = loginItem.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("wyoming-piper") {
                LabeledContent("Installiert", value: server.detectedVersion ?? "–")
                LabeledContent("Aktuell auf PyPI", value: checking ? "prüfe…" : (latest ?? "–"))
                HStack {
                    Button("Nach Update suchen") {
                        checking = true
                        Task { latest = await env.latestPiperVersion(); checking = false }
                    }
                    Button(env.isWorking ? "Aktualisiere…" : "Aktualisieren") { app.updatePiper() }
                        .disabled(env.isWorking || !isUpdateAvailable)
                    Spacer()
                }
                if let err = env.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Speicherort") {
                LabeledContent("Daten, Stimmen, Protokoll") {
                    Button(BundledRuntime.supportDirectory.path) {
                        NSWorkspace.shared.open(BundledRuntime.supportDirectory)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isUpdateAvailable: Bool {
        guard let latest, let current = server.detectedVersion else { return false }
        return AppSettings.isNewer(latest, than: current)
    }
}
