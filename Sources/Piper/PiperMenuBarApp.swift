import SwiftUI
import UserNotifications

/// Owns the long-lived managers and wires up lifecycle (notifications, server
/// auto-start, clean shutdown).
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: AppSettings
    let log: LogStore
    let env: EnvironmentManager
    let voices: VoiceManager
    let server: ServerController
    let loginItem: LoginItemManager
    let notifier: Notifier

    init() {
        let settings = AppSettings.shared
        let log = LogStore()
        let env = EnvironmentManager(log: log)
        let voices = VoiceManager(log: log)
        let notifier = Notifier()
        self.settings = settings
        self.log = log
        self.env = env
        self.voices = voices
        self.notifier = notifier
        self.server = ServerController(settings: settings, log: log, env: env, voices: voices, notifier: notifier)
        self.loginItem = LoginItemManager()
    }

    func bootstrap() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // The service is meant to come up at login: register as a login item on
        // the very first launch. Afterwards the menu toggle is authoritative.
        if !settings.didOfferLoginItem {
            settings.didOfferLoginItem = true
            loginItem.setEnabled(true)
            log.appendSystem(loginItem.isEnabled
                ? "Als Anmeldeobjekt registriert"
                : "Anmeldeobjekt nicht registriert: \(loginItem.lastError ?? "unbekannt")")
        }
        if settings.startOnLaunch { server.start() }
    }

    func shutdown() {
        server.terminateNow()
    }

    /// Switch the default voice: download it first if needed, then restart a
    /// running service so it takes effect.
    func selectVoice(_ voice: Voice) {
        Task {
            do {
                try await voices.ensureDownloaded(voice)
            } catch {
                return // error is shown in the menu and the log
            }
            guard settings.voice != voice.id || server.runningVoice != voice.id else { return }
            settings.voice = voice.id
            log.appendSystem("Standardstimme: \(voice.id)")
            if server.status.isActive { server.restart() }
        }
    }

    /// Stop, pip-upgrade wyoming-piper, restart if it was running.
    func updatePiper() {
        Task {
            let wasRunning = server.stopForMaintenance()
            while server.isRunning { try? await Task.sleep(nanoseconds: 200_000_000) }
            await env.updatePiper()
            if wasRunning { server.start() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon (also set via LSUIElement)
        env.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        env.shutdown()
    }
}

@main
struct PiperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let env = delegate.env

        MenuBarExtra {
            MenuContentView()
                .environmentObject(env)
                .environmentObject(env.settings)
                .environmentObject(env.server)
                .environmentObject(env.voices)
                .environmentObject(env.loginItem)
                .environmentObject(env.log)
        } label: {
            MenuBarLabel(server: env.server, voices: env.voices)
        }

        Settings {
            SettingsView()
                .environmentObject(env)
                .environmentObject(env.settings)
                .environmentObject(env.server)
                .environmentObject(env.voices)
                .environmentObject(env.loginItem)
                .environmentObject(env.env)
        }

        Window("Piper-Protokoll", id: "logs") {
            LogView()
                .environmentObject(env.log)
                .environmentObject(env.server)
                .environmentObject(env.settings)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Monochrome menu-bar icon that reflects the server status. SF Symbols render
/// as template images, so AppKit tints them for light/dark menu bars.
struct MenuBarLabel: View {
    @ObservedObject var server: ServerController
    @ObservedObject var voices: VoiceManager

    var body: some View {
        Image(systemName: symbolName)
            .accessibilityLabel("Piper")
    }

    private var symbolName: String {
        if voices.downloading != nil { return "arrow.down.circle" }
        switch server.status {
        case .running: return "waveform"
        case .installing: return "arrow.down.circle"
        case .starting, .stopping, .stopped: return "waveform.slash"
        case .crashed: return "exclamationmark.triangle.fill"
        }
    }
}
