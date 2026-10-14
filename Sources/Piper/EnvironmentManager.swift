import Foundation

/// Prepares the per-user Python virtualenv that wyoming-piper runs in.
///
/// On first launch (or after the bundled CPython minor version changes) it
/// creates a virtualenv from the bundled interpreter and pip-installs
/// wyoming-piper (which pulls piper-tts and onnxruntime) into
/// `~/Library/Piper/venv`. All pip/venv output is streamed into the shared
/// `LogStore` so the log window shows live progress.
@MainActor
final class EnvironmentManager: ObservableObject {

    /// True while a venv/pip operation is running (install or update).
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    private let log: LogStore

    init(log: LogStore) {
        self.log = log
    }

    enum EnvError: LocalizedError {
        case pythonMissing(String)
        case venvFailed(Int32)
        case installFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .pythonMissing(let path):
                return "Gebündeltes Python fehlt unter \(path)."
            case .venvFailed(let code):
                return "Python-Umgebung konnte nicht angelegt werden (Exit \(code))."
            case .installFailed(let code):
                return "Installation von wyoming-piper fehlgeschlagen (Exit \(code)) — Details im Protokoll."
            }
        }
    }

    // MARK: - Public

    /// Ensure the virtualenv exists and wyoming-piper is installed. Safe to call
    /// on every start — it is a fast no-op once everything is in place.
    func ensureReady(progress: @MainActor (String) -> Void) async throws {
        lastError = nil
        guard FileManager.default.isExecutableFile(atPath: BundledRuntime.bundledPythonURL.path) else {
            throw EnvError.pythonMissing(BundledRuntime.bundledPythonURL.path)
        }
        try? FileManager.default.createDirectory(at: BundledRuntime.supportDirectory, withIntermediateDirectories: true)

        let venvPython = BundledRuntime.venvPythonURL
        // Recreate the venv if it is missing, or if the bundled Python minor
        // changed (a venv built on the old minor is unusable).
        let minorChanged = BundledRuntime.venvPythonMinor != nil
            && BundledRuntime.venvPythonMinor != BundledRuntime.bundledPythonMinor
        let needNewVenv = !FileManager.default.isExecutableFile(atPath: venvPython.path) || minorChanged

        if needNewVenv {
            isWorking = true
            defer { isWorking = false }
            if minorChanged {
                log.appendSystem("Python-Version geändert — Umgebung wird neu angelegt")
            }
            progress("Erstelle Python-Umgebung…")
            try? FileManager.default.removeItem(at: BundledRuntime.venvRoot)
            log.appendSystem("Lege virtualenv an: \(BundledRuntime.venvRoot.path)")
            let code = try await runStreaming(BundledRuntime.bundledPythonURL,
                                              ["-m", "venv", "--copies", BundledRuntime.venvRoot.path])
            guard code == 0 else { throw EnvError.venvFailed(code) }

            progress("Aktualisiere pip…")
            _ = try await runStreaming(venvPython, ["-m", "pip", "install", "--upgrade", "pip"])
        }

        if !BundledRuntime.isPiperInstalled {
            isWorking = true
            defer { isWorking = false }
            progress("Installiere wyoming-piper…")
            log.appendSystem("Installiere \(BundledRuntime.piperPackage) per pip…")
            let code = try await runStreaming(venvPython, ["-m", "pip", "install", BundledRuntime.piperPackage])
            guard code == 0 else { throw EnvError.installFailed(code) }
            log.appendSystem("wyoming-piper \(BundledRuntime.installedPiperVersion ?? "?") installiert")
        }
    }

    /// Upgrade wyoming-piper (and with it piper-tts) to the latest version on
    /// PyPI. The caller is expected to stop the server first and restart it.
    @discardableResult
    func updatePiper() async -> Bool {
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await ensureReady(progress: { _ in })
            log.appendSystem("Aktualisiere wyoming-piper per pip…")
            let code = try await runStreaming(BundledRuntime.venvPythonURL,
                                              ["-m", "pip", "install", "--upgrade", BundledRuntime.piperPackage])
            guard code == 0 else { throw EnvError.installFailed(code) }
            log.appendSystem("wyoming-piper ist jetzt \(BundledRuntime.installedPiperVersion ?? "?"), "
                + "piper-tts \(BundledRuntime.installedVersion(module: "piper_tts") ?? "?")")
            return true
        } catch {
            lastError = error.localizedDescription
            log.appendSystem("Update fehlgeschlagen: \(error.localizedDescription)")
            return false
        }
    }

    /// Latest wyoming-piper version on PyPI, or nil if PyPI is unreachable.
    func latestPiperVersion() async -> String? {
        guard let url = URL(string: "https://pypi.org/pypi/\(BundledRuntime.piperPackage)/json") else { return nil }
        struct PyPI: Decodable { struct Info: Decodable { let version: String }; let info: Info }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(PyPI.self, from: data) else { return nil }
        return parsed.info.version
    }

    // MARK: - Process streaming

    /// Run a process, streaming combined stdout/stderr into the log, and return
    /// its exit code.
    private func runStreaming(_ executable: URL, _ args: [String]) async throws -> Int32 {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.log.append(text) }
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            proc.terminationHandler = { [weak self] p in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.availableData
                if !rest.isEmpty, let text = String(data: rest, encoding: .utf8) {
                    Task { @MainActor [weak self] in self?.log.append(text) }
                }
                cont.resume(returning: p.terminationStatus)
            }
            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }
}
