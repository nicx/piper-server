import Foundation

/// A Piper voice from the official catalogue (huggingface.co/rhasspy/piper-voices).
struct Voice: Identifiable, Hashable {
    /// File stem and the name wyoming-piper/Home Assistant use, e.g. "de_DE-thorsten-high".
    let id: String
    /// Path below the repository root, e.g. "de/de_DE/thorsten/high".
    let repoPath: String
    let displayName: String
    let quality: String
    /// Approximate download size in MB (from voices.json), for the menu.
    let sizeMB: Int
    /// Licence of the training data, as stated in the voice's MODEL_CARD.
    let license: String

    var onnxFile: String { "\(id).onnx" }
    var configFile: String { "\(id).onnx.json" }
}

/// The German voices. Checked against voices.json and the MODEL_CARDs on
/// 2026-10-14; Ramona, Karlsson and Eva K. only exist in low/x_low quality.
enum VoiceCatalog {
    static let german: [Voice] = [
        Voice(id: "de_DE-thorsten-high", repoPath: "de/de_DE/thorsten/high",
              displayName: "Thorsten", quality: "hoch", sizeMB: 114, license: "CC0"),
        Voice(id: "de_DE-thorsten-medium", repoPath: "de/de_DE/thorsten/medium",
              displayName: "Thorsten", quality: "mittel", sizeMB: 63, license: "CC0"),
        Voice(id: "de_DE-thorsten-low", repoPath: "de/de_DE/thorsten/low",
              displayName: "Thorsten", quality: "niedrig", sizeMB: 63, license: "CC0"),
        Voice(id: "de_DE-thorsten_emotional-medium", repoPath: "de/de_DE/thorsten_emotional/medium",
              displayName: "Thorsten (emotional)", quality: "mittel", sizeMB: 76, license: "CC0"),
        Voice(id: "de_DE-kerstin-low", repoPath: "de/de_DE/kerstin/low",
              displayName: "Kerstin", quality: "niedrig", sizeMB: 63, license: "CC0"),
        Voice(id: "de_DE-ramona-low", repoPath: "de/de_DE/ramona/low",
              displayName: "Ramona", quality: "niedrig", sizeMB: 63, license: "M-AILABS"),
        Voice(id: "de_DE-karlsson-low", repoPath: "de/de_DE/karlsson/low",
              displayName: "Karlsson", quality: "niedrig", sizeMB: 63, license: "M-AILABS"),
        Voice(id: "de_DE-eva_k-x_low", repoPath: "de/de_DE/eva_k/x_low",
              displayName: "Eva K.", quality: "sehr niedrig", sizeMB: 20, license: "M-AILABS"),
        Voice(id: "de_DE-pavoque-low", repoPath: "de/de_DE/pavoque/low",
              displayName: "Pavoque", quality: "niedrig", sizeMB: 63, license: "CC BY-NC-SA 4.0"),
        Voice(id: "de_DE-mls-medium", repoPath: "de/de_DE/mls/medium",
              displayName: "MLS (236 Sprecher)", quality: "mittel", sizeMB: 76, license: "CC BY 4.0"),
    ]

    static func voice(id: String) -> Voice? { german.first { $0.id == id } }

    static let baseURL = URL(string: "https://huggingface.co/rhasspy/piper-voices/resolve/main/")!
}

/// Downloads voice models into `~/Library/Piper/voices` with progress, and
/// reports which voices are on disk. wyoming-piper finds a voice there as
/// `<id>.onnx` + `<id>.onnx.json`.
@MainActor
final class VoiceManager: ObservableObject {

    /// Voice currently being downloaded, and its progress 0…1.
    @Published private(set) var downloading: Voice?
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?
    /// Bumped after every download/delete so views re-evaluate `isInstalled`.
    @Published private(set) var revision = 0

    private let log: LogStore

    init(log: LogStore) {
        self.log = log
    }

    enum DownloadError: LocalizedError {
        case http(Int, String)
        case busy

        var errorDescription: String? {
            switch self {
            case .http(let code, let file): return "Download von \(file) fehlgeschlagen (HTTP \(code))."
            case .busy: return "Es läuft bereits ein Download."
            }
        }
    }

    func isInstalled(_ id: String) -> Bool {
        let dir = BundledRuntime.voicesDirectory
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("\(id).onnx").path)
            && fm.fileExists(atPath: dir.appendingPathComponent("\(id).onnx.json").path)
    }

    /// Download a voice unless it is already on disk. The small config is
    /// fetched first and the model last, each into a temp file that is moved
    /// into place only when complete — so a cancelled download never leaves a
    /// half file that wyoming-piper would try to load.
    func ensureDownloaded(_ voice: Voice) async throws {
        if isInstalled(voice.id) { return }
        guard downloading == nil else { throw DownloadError.busy }
        downloading = voice
        progress = 0
        lastError = nil
        defer { downloading = nil; revision += 1 }

        let dir = BundledRuntime.voicesDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        log.appendSystem("Lade Stimme \(voice.id) (~\(voice.sizeMB) MB) von Hugging Face…")
        do {
            try await fetch(voice.repoPath + "/" + voice.configFile, to: dir.appendingPathComponent(voice.configFile), reportsProgress: false)
            try await fetch(voice.repoPath + "/" + voice.onnxFile, to: dir.appendingPathComponent(voice.onnxFile), reportsProgress: true)
        } catch {
            lastError = error.localizedDescription
            log.appendSystem("Download von \(voice.id) fehlgeschlagen: \(error.localizedDescription)")
            throw error
        }
        log.appendSystem("Stimme \(voice.id) geladen")
    }

    /// Delete a voice's files (not the active one — the caller checks).
    func remove(_ voice: Voice) {
        let dir = BundledRuntime.voicesDirectory
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(voice.onnxFile))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(voice.configFile))
        log.appendSystem("Stimme \(voice.id) gelöscht")
        revision += 1
    }

    private func fetch(_ path: String, to destination: URL, reportsProgress: Bool) async throws {
        let url = VoiceCatalog.baseURL.appendingPathComponent(path)
        let delegate = ProgressDelegate { [weak self] fraction in
            guard reportsProgress else { return }
            Task { @MainActor [weak self] in self?.progress = fraction }
        }
        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw DownloadError.http(status, destination.lastPathComponent)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}

/// Per-task delegate that forwards download progress.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    // Required by the protocol; the async `download(from:delegate:)` API hands
    // the file to the caller itself.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
