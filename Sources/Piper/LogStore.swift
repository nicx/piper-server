import Foundation

/// Captures wyoming-piper's stdout/stderr (and the first-run pip install
/// output) into an in-memory ring buffer for the log window, and appends every
/// line to `~/Library/Piper/logs/piper.log`.
@MainActor
final class LogStore: ObservableObject {
    /// Most recent log lines, newest last. Capped at `capacity`.
    @Published private(set) var lines: [String] = []

    private let capacity = 4000
    private let fileHandle: FileHandle?
    let logFileURL: URL

    init() {
        let dir = BundledRuntime.logsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("piper.log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        _ = try? fileHandle?.seekToEnd()
    }

    deinit {
        try? fileHandle?.close()
    }

    /// Append a raw chunk (may contain multiple newline-separated lines).
    func append(_ chunk: String) {
        let incoming = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in incoming where !line.isEmpty {
            lines.append(line)
        }
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        if let data = chunk.data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
        }
    }

    func appendSystem(_ message: String) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.space))
        append("[Piper \(stamp)] \(message)\n")
    }

    func clear() {
        lines.removeAll()
    }
}
