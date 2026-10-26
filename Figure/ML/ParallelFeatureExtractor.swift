import CoreGraphics
import Foundation

nonisolated struct ExtractedSample: Sendable {
    let image: LabeledImage
    let features: [Double]
}

/// Feature extraction is the expensive, embarrassingly parallel part of the pipeline: every
/// image goes through Otsu thresholding, connected components, convex hull and resampling
/// independently of the others. A task group keeps exactly one task per CPU core in flight, so
/// all cores stay busy without allocating hundreds of decoded images at once.
nonisolated enum ParallelFeatureExtractor {
    static var coreCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// - Parameter workers: number of concurrent tasks; `1` gives the sequential baseline used
    ///   by the benchmark.
    /// - Parameter onProgress: called with (done, total) every 1 % of the images.
    static func extract(
        _ images: [LabeledImage],
        workers: Int = coreCount,
        onProgress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> (samples: [ExtractedSample], failed: [LabeledImage]) {
        let total = images.count
        var results = [ExtractedSample?](repeating: nil, count: total)
        var failed: [LabeledImage] = []
        var done = 0
        // Reporting is throttled to 1 % steps: a main-actor hop per image costs about as much as
        // processing the image and would serialise the workers on the UI thread.
        let step = max(1, total / 100)

        try await withThrowingTaskGroup(of: (Int, [Double]?).self) { group in
            var next = 0
            func enqueue() {
                guard next < total else { return }
                let index = next
                let item = images[index]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    return (index, features(of: item.url))
                }
            }

            for _ in 0..<max(1, min(workers, total)) { enqueue() }

            while let (index, values) = try await group.next() {
                if let values {
                    results[index] = ExtractedSample(image: images[index], features: values)
                } else {
                    failed.append(images[index])
                }
                done += 1
                enqueue()
                if done % step == 0 || done == total { await onProgress(done, total) }
            }
        }

        return (results.compactMap { $0 }, failed)
    }

    static func features(of url: URL) -> [Double]? {
        guard let image = TrainingDataset.loadImage(url),
              let grayscale = ImagePreprocessor.grayscale(from: image),
              let features = FeatureExtractor.extract(from: grayscale)
        else { return nil }
        return features.values
    }
}
