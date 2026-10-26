import Foundation
import Observation

/// Journal of everything the app does: shown on the «Лог» tab and appended to
/// `Documents/operations.log` so it survives relaunches and can be shared.
@MainActor
@Observable
final class OperationLog {
    static let shared = OperationLog()

    struct Entry: Identifiable, Sendable {
        enum Level: String, Sendable { case info = "INFO", success = "OK", warning = "WARN", error = "ERROR" }
        let id = UUID()
        let date: Date
        let level: Level
        let message: String

        var line: String {
            "\(OperationLog.timestamp.string(from: date)) [\(level.rawValue)] \(message)"
        }
    }

    private(set) var entries: [Entry] = []

    nonisolated static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    nonisolated static var fileURL: URL {
        URL.documentsDirectory.appending(path: "operations.log")
    }

    func add(_ message: String, level: Entry.Level = .info) {
        let entry = Entry(date: .now, level: level, message: message)
        entries.append(entry)
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
        append(entry.line + "\n")
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func append(_ text: String) {
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Self.fileURL)
        }
    }
}
