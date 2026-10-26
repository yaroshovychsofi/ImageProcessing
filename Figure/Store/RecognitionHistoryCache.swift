import Foundation

enum RecognitionHistoryCache {
    private static let fileName = "recognition-history.json"

    static func load() -> [RecognitionRecord] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([RecognitionRecord].self, from: data)
        } catch {
            return []
        }
    }

    static func save(_ records: [RecognitionRecord]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A cache failure must not interrupt recognition or navigation.
        }
    }

    private static var fileURL: URL {
        let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        return cacheDirectory
            .appending(path: "FigureRecognition", directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }
}
