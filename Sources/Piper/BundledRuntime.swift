import Foundation

/// Resolves the bundled CPython runtime, the per-user data folder and builds
/// the argument list for launching wyoming-piper.
///
/// Layout produced by `Scripts/bundle-runtime.sh` (embedded in the `.app`):
/// ```
/// Runtime/python/bin/python3        # relocatable CPython 3.14 (arm64)
/// Runtime/python/lib/python3.14/    # standard library
/// ```
/// In a packaged `.app` this lives under `Contents/Resources/Runtime`; during
/// `swift run` we fall back to `<packageRoot>/Runtime`. Overridable with the
/// `PIPER_RUNTIME_DIR` environment variable.
///
/// Everything the app writes lives in ONE folder, `~/Library/Piper`:
/// ```
/// ~/Library/Piper/venv/     virtualenv with wyoming-piper (created on first launch)
/// ~/Library/Piper/voices/   downloaded voice models (<name>.onnx + .onnx.json)
/// ~/Library/Piper/logs/     piper.log
/// ```
enum BundledRuntime {

    enum RuntimeError: LocalizedError {
        case pythonMissing(String)
        case piperMissing

        var errorDescription: String? {
            switch self {
            case .pythonMissing(let path):
                return "Gebündeltes Python fehlt unter \(path). Scripts/bundle-runtime.sh ausführen."
            case .piperMissing:
                return "wyoming-piper ist noch nicht in der Python-Umgebung installiert."
            }
        }
    }

    // MARK: - Bundled interpreter (read-only, inside the .app)

    /// Root directory containing `python/`.
    static var runtimeRoot: URL {
        if let override = ProcessInfo.processInfo.environment["PIPER_RUNTIME_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("Runtime", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("python").path) {
                return bundled
            }
        }
        // Dev fallback: <packageRoot>/Runtime, derived from this file's location.
        // BundledRuntime.swift -> Piper -> Sources -> <packageRoot>
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Runtime", isDirectory: true)
    }

    /// The relocatable interpreter shipped inside the bundle.
    static var bundledPythonURL: URL {
        runtimeRoot.appendingPathComponent("python/bin/python3")
    }

    // MARK: - Per-user data folder (writable, outside the .app)

    /// `~/Library/Piper` — the single folder holding venv, voices and logs.
    /// Kept free of spaces like the sibling apps (`~/Library/ESPHome`, …).
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Piper", isDirectory: true)
    }

    static var venvRoot: URL { supportDirectory.appendingPathComponent("venv", isDirectory: true) }
    static var voicesDirectory: URL { supportDirectory.appendingPathComponent("voices", isDirectory: true) }
    static var logsDirectory: URL { supportDirectory.appendingPathComponent("logs", isDirectory: true) }

    /// The interpreter inside the virtualenv (used to launch wyoming-piper).
    static var venvPythonURL: URL { venvRoot.appendingPathComponent("bin/python") }

    // MARK: - Version helpers

    /// The `python3.X` directory name under a CPython tree's `lib/`. Used to
    /// detect a Python-minor mismatch between the bundled runtime and an existing
    /// virtualenv (which requires recreating the venv).
    static func pythonMinorName(under root: URL) -> String? {
        let lib = root.appendingPathComponent("lib")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: lib.path)) ?? []
        return entries.first { $0.hasPrefix("python3.") }
    }

    static var bundledPythonMinor: String? {
        pythonMinorName(under: runtimeRoot.appendingPathComponent("python"))
    }

    static var venvPythonMinor: String? {
        pythonMinorName(under: venvRoot)
    }

    static var venvSitePackagesURL: URL? {
        guard let minor = venvPythonMinor else { return nil }
        return venvRoot.appendingPathComponent("lib/\(minor)/site-packages", isDirectory: true)
    }

    /// pip package and importable module of the service.
    static let piperPackage = "wyoming-piper"
    static let piperModule = "wyoming_piper"

    /// Installed version of a package, read from its `<module>-<version>.dist-info`
    /// directory name in site-packages (no interpreter launch needed).
    static func installedVersion(module: String) -> String? {
        guard let site = venvSitePackagesURL,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: site.path) else { return nil }
        guard let info = entries.first(where: {
            $0.hasPrefix("\(module)-") && $0.hasSuffix(".dist-info")
        }) else { return nil }
        let version = info.dropFirst("\(module)-".count).dropLast(".dist-info".count)
        return version.isEmpty ? nil : String(version)
    }

    static var installedPiperVersion: String? { installedVersion(module: piperModule) }
    static var isPiperInstalled: Bool { installedPiperVersion != nil }

    // MARK: - Launch

    static func validate() throws {
        guard FileManager.default.isExecutableFile(atPath: bundledPythonURL.path) else {
            throw RuntimeError.pythonMissing(bundledPythonURL.path)
        }
        guard FileManager.default.isExecutableFile(atPath: venvPythonURL.path), isPiperInstalled else {
            throw RuntimeError.piperMissing
        }
    }

    /// The `--uri` wyoming-piper listens on.
    @MainActor
    static func uri(for settings: AppSettings) -> String {
        "tcp://\(settings.bindAddress):\(settings.port)"
    }

    /// Arguments passed to `venvPythonURL`. `--voice` is the default voice used
    /// when Home Assistant does not ask for a specific one; voices requested by
    /// name that are not on disk yet are fetched by wyoming-piper itself into
    /// the same folder.
    @MainActor
    static func arguments(for settings: AppSettings) -> [String] {
        var args = ["-m", piperModule,
                    "--uri", uri(for: settings),
                    "--voice", settings.voice,
                    "--data-dir", voicesDirectory.path]
        if settings.verbose { args.append("--debug") }
        return args
    }
}
