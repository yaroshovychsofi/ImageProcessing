import CoreGraphics
import Foundation

nonisolated enum RecognitionError: LocalizedError {
    case unreadableImage
    case noFigureFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Не вдалося прочитати зображення."
        case .noFigureFound:
            "На зображенні не знайдено жодної фігури. Спробуйте чіткіше зображення з однією фігурою на однотонному тлі."
        }
    }
}

/// Indices follow the class order of the trainer (`Tools/Trainer/dataset.js`): circle, square,
/// triangle — the same order as `FigureClass.allCases`. The recogniser stays label-agnostic so
/// that nothing in the recognition pipeline has to touch main-actor-isolated view models.
nonisolated struct RecognitionOutcome: Sendable {
    let outputs: [Double]
    let normalised: [Double]
    let bestIndex: Int
    let cells: [Double]
    let geometry: ShapeGeometry
    let duration: Duration
    /// Which weights answered: the bundled model or the one trained in the app.
    let usedTrainedModel: Bool

    var confidence: Double { normalised[bestIndex] }
}

/// Loads the Brain.js model shipped with the app and evaluates images off the main actor.
actor FigureRecognizer {
    static let shared = FigureRecognizer()

    // The network is a closed three-class classifier: it answers "circle", "square" or
    // "triangle" for whatever it is given. A compactness gate used to reject photographs that
    // contain no figure, but once hand-drawn outlines entered the training set the two
    // populations started to overlap — a cheap geometric test cannot separate them, so the
    // gate was removed rather than left as a check that quietly rejects real drawings.

    private struct LoadedModel: Sendable {
        let network: BrainNetwork
        let confidenceTemperature: Double
        var isTrained = false
    }

    private var cachedModel: LoadedModel?

    /// Model trained inside the app; it replaces the bundled one until reset.
    nonisolated static var trainedModelURL: URL {
        URL.documentsDirectory.appending(path: "trained-model.json")
    }

    var usesTrainedModel: Bool {
        FileManager.default.fileExists(atPath: Self.trainedModelURL.path())
    }

    /// Activates a freshly trained Brain.js model and keeps it for later launches.
    func install(trainedModel data: Data) throws {
        let network = try BrainNetwork(data: data)
        try data.write(to: Self.trainedModelURL, options: .atomic)
        cachedModel = LoadedModel(network: network, confidenceTemperature: 1, isTrained: true)
    }

    /// The model trained by `Tools/Trainer`, regardless of which one is active.
    nonisolated static func bundledNetwork() throws -> BrainNetwork {
        guard let url = Bundle.main.url(forResource: "model", withExtension: "json") else {
            throw BrainNetworkError.modelMissing
        }
        return try BrainNetwork(data: try Data(contentsOf: url))
    }

    func resetToBundledModel() {
        try? FileManager.default.removeItem(at: Self.trainedModelURL)
        cachedModel = nil
    }

    func network() throws -> BrainNetwork {
        try loadedModel().network
    }

    private func loadedModel() throws -> LoadedModel {
        if let cachedModel { return cachedModel }

        if let data = try? Data(contentsOf: Self.trainedModelURL),
           let network = try? BrainNetwork(data: data),
           network.inputSize == FeatureExtractor.featureCount {
            let model = LoadedModel(network: network, confidenceTemperature: 1, isTrained: true)
            cachedModel = model
            return model
        }

        guard let url = Bundle.main.url(forResource: "model", withExtension: "json") else {
            throw BrainNetworkError.modelMissing
        }
        let network = try BrainNetwork(data: try Data(contentsOf: url))
        guard network.inputSize == FeatureExtractor.featureCount else {
            throw BrainNetworkError.malformedModel("модель очікує \(network.inputSize) ознак замість \(FeatureExtractor.featureCount)")
        }

        let model = LoadedModel(
            network: network,
            confidenceTemperature: Self.loadConfidenceTemperature()
        )
        cachedModel = model
        return model
    }

    private nonisolated static func loadConfidenceTemperature() -> Double {
        guard let url = Bundle.main.url(forResource: "metrics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let calibration = root["calibration"] as? [String: Any],
              let temperature = calibration["temperature"] as? Double,
              temperature.isFinite,
              temperature > 0
        else { return 1 }
        return temperature
    }

    /// Progress is reported at phase boundaries only: the phases themselves are tight loops
    /// where a callback per pixel would cost more than the work it reports on.
    func recognise(_ image: CGImage, onProgress: @Sendable (Double) async -> Void = { _ in }) async throws -> RecognitionOutcome {
        let model = try loadedModel()
        let network = model.network
        let clock = ContinuousClock()
        let started = clock.now

        await onProgress(0.15)
        guard let grayscale = ImagePreprocessor.grayscale(from: image) else {
            throw RecognitionError.unreadableImage
        }

        await onProgress(0.45)
        await onProgress(0.75)
        guard let features = FeatureExtractor.extract(from: grayscale) else {
            throw RecognitionError.noFigureFound
        }

        await onProgress(0.9)
        let outputs = network.run(features.values)
        let normalisedOutputs = BrainNetwork.calibratedProbabilities(
            from: outputs,
            temperature: model.confidenceTemperature
        )

        var bestIndex = 0
        for index in 1..<outputs.count where outputs[index] > outputs[bestIndex] {
            bestIndex = index
        }

        await onProgress(1)
        return RecognitionOutcome(
            outputs: outputs,
            normalised: normalisedOutputs,
            bestIndex: bestIndex,
            cells: features.cells,
            geometry: features.geometry,
            duration: clock.now - started,
            usedTrainedModel: model.isTrained
        )
    }

    func previewCells(for image: CGImage) throws -> [Double] {
        guard let grayscale = ImagePreprocessor.grayscale(from: image),
              let features = FeatureExtractor.extract(from: grayscale)
        else { throw RecognitionError.noFigureFound }
        return features.cells
    }
}
