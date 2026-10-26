import CoreGraphics
import Foundation
import ImageIO

/// Image groups bundled under `Resources/Assets`, split by source quality so the user can
/// train on one group or on all of them together.
nonisolated enum AssetGroup: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case generated = "generated_200"
    case handdrawn = "handdrawn_70"

    var id: Self { self }

    var title: String {
        switch self {
        case .generated: "Згенеровані 200×200"
        case .handdrawn: "Рукописні 70×70"
        }
    }
}

nonisolated struct LabeledImage: Sendable, Hashable {
    let url: URL
    let classIndex: Int
    let group: AssetGroup
}

nonisolated enum TrainingDataset {
    static let classNames = ["circle", "square", "triangle"]

    static var assetsRoot: URL? {
        Bundle.main.url(forResource: "Assets", withExtension: nil)
    }

    /// The bundle never changes at runtime, so the folders are scanned once.
    private static let catalogue: [AssetGroup: [LabeledImage]] = {
        var result: [AssetGroup: [LabeledImage]] = [:]
        for group in AssetGroup.allCases { result[group] = scan(group) }
        return result
    }()

    static func count(in group: AssetGroup) -> Int {
        catalogue[group]?.count ?? 0
    }

    /// All images of the chosen groups, ordered by group, class and file name.
    static func images(in groups: Set<AssetGroup>) -> [LabeledImage] {
        AssetGroup.allCases.filter(groups.contains).flatMap { catalogue[$0] ?? [] }
    }

    private static func scan(_ group: AssetGroup) -> [LabeledImage] {
        guard let root = assetsRoot else { return [] }
        let manager = FileManager.default
        var result: [LabeledImage] = []
        do {
            for (classIndex, name) in classNames.enumerated() {
                let folder = root.appending(path: group.rawValue).appending(path: name)
                let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                result += files
                    .filter { $0.pathExtension.lowercased() == "png" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    .map { LabeledImage(url: $0, classIndex: classIndex, group: group) }
            }
        }
        return result
    }

    /// Takes `limit` images balanced over classes, then splits every class into train and test
    /// with the same proportion. A fixed seed keeps runs comparable for benchmarks.
    static func split(_ images: [LabeledImage], limit: Int, testFraction: Double, seed: UInt64) -> (train: [LabeledImage], test: [LabeledImage]) {
        var generator = SeededGenerator(seed: seed)
        let perClass = max(1, limit / classNames.count)
        var train: [LabeledImage] = []
        var test: [LabeledImage] = []
        for classIndex in classNames.indices {
            let chosen = images.filter { $0.classIndex == classIndex }.shuffled(using: &generator).prefix(perClass)
            let testCount = Int((Double(chosen.count) * testFraction).rounded())
            test += chosen.prefix(testCount)
            train += chosen.dropFirst(testCount)
        }
        return (train.shuffled(using: &generator), test)
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// SplitMix64: reproducible shuffling for dataset splits.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
