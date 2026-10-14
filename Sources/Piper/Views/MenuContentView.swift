import SwiftUI
import AppKit

/// The menu shown when the user clicks the menu-bar icon.
struct MenuContentView: View {
    @EnvironmentObject var app: AppEnvironment
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var server: ServerController
    @EnvironmentObject var voices: VoiceManager
    @EnvironmentObject var loginItem: LoginItemManager
    @EnvironmentObject var log: LogStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(statusLine)
        Text(detailLine).font(.caption)
        if let voice = voices.downloading {
            Text("Lade \(voice.displayName) (\(voice.quality)) … \(Int(voices.progress * 100)) %").font(.caption)
        } else if let err = voices.lastError {
            Text(err).font(.caption)
        }

        Divider()

        Button("Starten") { server.start() }
            .disabled(server.status.isActive)
        Button("Stoppen") { server.stop() }
            .disabled(!server.status.isActive)
        Button("Neu starten") { server.restart() }
            .disabled(!server.status.isActive)

        Divider()

        Menu("Stimme") {
            ForEach(VoiceCatalog.german) { voice in
                Button {
                    app.selectVoice(voice)
                } label: {
                    Text(voiceLabel(voice))
                }
                .disabled(voices.downloading != nil)
            }
        }

        Divider()

        Button("Protokoll anzeigen…") { openWindow(id: "logs"); NSApp.activate(ignoringOtherApps: true) }
        Button("Protokolldatei öffnen") { NSWorkspace.shared.open(log.logFileURL) }
        Button("Datenordner im Finder zeigen") { NSWorkspace.shared.open(BundledRuntime.supportDirectory) }

        Divider()

        Toggle("Beim Anmelden starten", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))

        // Not `SettingsLink`: as an accessory app (LSUIElement) we are not
        // activated by opening a window, so the settings window would appear
        // behind whatever the user is looking at. Activate first, then open
        // (same pattern as the ESPHome and Matter apps).
        Button("Einstellungen…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Button("Piper beenden") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func voiceLabel(_ voice: Voice) -> String {
        let _ = voices.revision // re-evaluate after downloads
        let mark = voice.id == settings.voice ? "✓ " : "    "
        let state = voices.isInstalled(voice.id) ? "" : " · ↓ \(voice.sizeMB) MB"
        return "\(mark)\(voice.displayName) (\(voice.quality))\(state)"
    }

    private var statusLine: String {
        switch server.status {
        case .stopped: return "Piper gestoppt"
        case .installing(let message): return message
        case .starting: return "Piper startet…"
        case .stopping: return "Piper stoppt…"
        case .crashed(let reason): return "Piper abgestürzt (\(reason))"
        case .running:
            let uptime = server.uptimeDescription.map { " · seit \($0)" } ?? ""
            return "Piper läuft · \(settings.bindAddress):\(settings.port)\(uptime)"
        }
    }

    private var detailLine: String {
        let voice = VoiceCatalog.voice(id: server.runningVoice ?? settings.voice)
        let voiceText = voice.map { "\($0.displayName) (\($0.quality))" } ?? settings.voice
        let version = server.detectedVersion.map { "wyoming-piper \($0)" } ?? "wyoming-piper nicht installiert"
        return "\(version) · Stimme \(voiceText)"
    }
}
