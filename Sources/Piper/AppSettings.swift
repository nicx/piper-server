import Foundation

/// User-facing configuration, persisted in `UserDefaults`.
///
/// Every property writes through to `UserDefaults` on `didSet` so that the
/// `ServerController` always reads the current values, and SwiftUI views can
/// bind directly via `@Published`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Wyoming default port for Piper.
    static let defaultPort = 10200
    static let defaultVoice = "de_DE-thorsten-high"

    /// Bind addresses offered in the settings: only this Mac, or all interfaces.
    static let loopbackAddress = "127.0.0.1"
    static let anyAddress = "0.0.0.0"

    /// TCP port wyoming-piper listens on (passed as `--uri tcp://<bind>:<port>`).
    @Published var port: Int { didSet { defaults.set(port, forKey: Keys.port) } }
    /// Address wyoming-piper binds to. Loopback is enough when Home Assistant
    /// runs on the same Mac; `0.0.0.0` makes it reachable from the LAN.
    @Published var bindAddress: String { didSet { defaults.set(bindAddress, forKey: Keys.bindAddress) } }
    /// Default voice (file stem, e.g. "de_DE-thorsten-high").
    @Published var voice: String { didSet { defaults.set(voice, forKey: Keys.voice) } }
    /// Pass `--debug` to wyoming-piper.
    @Published var verbose: Bool { didSet { defaults.set(verbose, forKey: Keys.verbose) } }
    @Published var autoRestart: Bool { didSet { defaults.set(autoRestart, forKey: Keys.autoRestart) } }
    /// Start the service as soon as the app launches (and so at login, when
    /// the app is a login item).
    @Published var startOnLaunch: Bool { didSet { defaults.set(startOnLaunch, forKey: Keys.startOnLaunch) } }

    /// Whether the app already registered itself as a login item once. The
    /// first launch does that automatically; afterwards the menu toggle rules.
    var didOfferLoginItem: Bool {
        get { defaults.bool(forKey: Keys.didOfferLoginItem) }
        set { defaults.set(newValue, forKey: Keys.didOfferLoginItem) }
    }

    private init() {
        port = (defaults.object(forKey: Keys.port) as? Int) ?? AppSettings.defaultPort
        bindAddress = defaults.string(forKey: Keys.bindAddress) ?? AppSettings.loopbackAddress
        voice = defaults.string(forKey: Keys.voice) ?? AppSettings.defaultVoice
        verbose = (defaults.object(forKey: Keys.verbose) as? Bool) ?? false
        autoRestart = (defaults.object(forKey: Keys.autoRestart) as? Bool) ?? true
        startOnLaunch = (defaults.object(forKey: Keys.startOnLaunch) as? Bool) ?? true
    }

    /// Compare dotted version strings. True if `candidate` is strictly newer.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private enum Keys {
        static let port = "server.port"
        static let bindAddress = "server.bindAddress"
        static let voice = "server.voice"
        static let verbose = "server.verbose"
        static let autoRestart = "server.autoRestart"
        static let startOnLaunch = "server.startOnLaunch"
        static let didOfferLoginItem = "app.didOfferLoginItem"
    }
}
