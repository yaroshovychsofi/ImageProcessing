import Foundation
import Observation

nonisolated struct EpochPoint: Identifiable, Sendable, Codable {
    var id: Int { epoch }
    let epoch: Int
    let error: Double
    var trainAccuracy: Double?
    var testAccuracy: Double?
}

nonisolated struct MisclassifiedImage: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let expected: Int
    let predicted: Int
}

nonisolated struct TrainingResult: Sendable {
    let config: TrainingConfig
    let groups: [AssetGroup]
    let trainCount: Int
    let testCount: Int
    let workers: Int
    let epochsDone: Int
    let finalError: Double
    let trainAccuracy: Double
    let testAccuracy: Double
    /// confusion[expected][predicted]
    let confusion: [[Int]]
    let misclassified: [MisclassifiedImage]
    let extractionTime: Duration
    let trainingTime: Duration
    let totalTime: Duration
    let modelJSON: Data
    /// Accuracy of the bundled model on the same test images, for comparison.
    let bundledTestAccuracy: Double?
}

nonisolated struct BenchmarkResult: Sendable {
    let images: Int
    let sequential: Duration
    let parallel: Duration
    let workers: Int

    var speedup: Double { sequential / parallel }
}

@MainActor
@Observable
final class TrainingStore {
    enum Phase: Equatable {
        case idle, extracting, training, evaluating, finished, cancelled, failed(String)

        var title: String {
            switch self {
            case .idle: "Готово до навчання"
            case .extracting: "Обробка зображень"
            case .training: "Навчання мережі"
            case .evaluating: "Оцінювання"
            case .finished: "Навчання завершено"
            case .cancelled: "Зупинено користувачем"
            case .failed(let message): "Помилка: \(message)"
            }
        }
    }

    // Settings
    var groups: Set<AssetGroup> = Set(AssetGroup.allCases)
    var imageLimit = TrainingDataset.images(in: Set(AssetGroup.allCases)).count
    var testFraction = 0.2
    var parallel = true
    var config = TrainingConfig()

    // Live state
    private(set) var phase = Phase.idle
    private(set) var processed = 0
    private(set) var toProcess = 0
    private(set) var epoch = 0
    private(set) var currentError: Double?
    private(set) var history: [EpochPoint] = []
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var phaseStartedAt: Date?
    private(set) var extractionTime: Duration?
    private(set) var trainingTime: Duration?
    private(set) var result: TrainingResult?
    private(set) var benchmark: BenchmarkResult?
    private(set) var isBenchmarking = false
    private(set) var benchmarkProcessed = 0
    private(set) var benchmarkTotal = 0
    private(set) var usesTrainedModel = false
    private(set) var resultApplied = false

    private var task: Task<Void, Never>?
    private let log = OperationLog.shared

    var isRunning: Bool { [.extracting, .training, .evaluating].contains(phase) }
    var availableImages: Int { TrainingDataset.images(in: groups).count }
    var workers: Int { parallel ? ParallelFeatureExtractor.coreCount : 1 }
    var extractionFraction: Double { toProcess == 0 ? 0 : Double(processed) / Double(toProcess) }
    var epochFraction: Double { Double(epoch) / Double(max(1, config.epochs)) }

    init() {
        Task { usesTrainedModel = await FigureRecognizer.shared.usesTrainedModel }
    }

    func start() {
        guard !isRunning, !groups.isEmpty else { return }
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
    }

    func resetModel() async {
        await FigureRecognizer.shared.resetToBundledModel()
        usesTrainedModel = false
        log.add("Відновлено вбудовану модель (навчену в Tools/Trainer).", level: .warning)
    }

    private func run() async {
        let clock = ContinuousClock()
        let config = self.config
        let groups = AssetGroup.allCases.filter { self.groups.contains($0) }
        let workers = self.workers
        result = nil
        history = []
        epoch = 0
        currentError = nil
        extractionTime = nil
        trainingTime = nil
        startedAt = .now
        endedAt = nil
        let started = clock.now

        let all = TrainingDataset.images(in: Set(groups))
        let split = TrainingDataset.split(all, limit: min(imageLimit, all.count), testFraction: testFraction, seed: 2025)
        log.add("Старт навчання: папки \(groups.map(\.rawValue).joined(separator: " + ")), \(split.train.count) навчальних і \(split.test.count) тестових зображень.")
        log.add("Параметри: епохи \(config.epochs), learning rate \(config.learningRate), momentum \(config.momentum), прихований шар \(config.hiddenNeurons), errorThresh \(config.errorThresh), потоків \(workers).")

        do {
            // 1. Parallel feature extraction.
            phase = .extracting
            phaseStartedAt = .now
            processed = 0
            toProcess = split.train.count + split.test.count
            let extractionStart = clock.now
            let extracted = try await ParallelFeatureExtractor.extract(split.train + split.test, workers: workers) { done, _ in
                await MainActor.run { self.processed = done }
            }
            let extraction = clock.now - extractionStart
            extractionTime = extraction
            let trainURLs = Set(split.train.map(\.url))
            let train = extracted.samples.filter { trainURLs.contains($0.image.url) }
            let test = extracted.samples.filter { !trainURLs.contains($0.image.url) }
            log.add("Ознаки (69 на зображення) обчислено за \(extraction.formattedSeconds) на \(workers) потоках; не вдалося обробити: \(extracted.failed.count).", level: .success)
            for item in extracted.failed { log.add("Пропущено \(item.url.lastPathComponent): фігуру не знайдено.", level: .warning) }

            // 2. Brain.js training, one epoch per step.
            phase = .training
            phaseStartedAt = .now
            let engine = BrainJSEngine()
            try await engine.prepare(train: train, test: test, config: config)
            let trainingStart = clock.now
            var lastError = 1.0
            for current in 1...max(1, config.epochs) {
                try Task.checkCancellation()
                lastError = try await engine.trainEpoch(current, config: config)
                var point = EpochPoint(epoch: current, error: lastError)
                let reachedThreshold = lastError < config.errorThresh
                if current == 1 || current % max(1, config.evaluateEvery) == 0 || current == config.epochs || reachedThreshold {
                    point.trainAccuracy = try await engine.accuracy(test: false)
                    point.testAccuracy = try await engine.accuracy(test: true)
                    log.add(String(format: "Епоха %d: помилка %.5f, точність train %.1f %%, test %.1f %%", current, lastError, (point.trainAccuracy ?? 0) * 100, (point.testAccuracy ?? 0) * 100))
                }
                history.append(point)
                epoch = current
                currentError = lastError
                trainingTime = clock.now - trainingStart
                if reachedThreshold {
                    log.add("Досягнуто errorThresh \(config.errorThresh) на епосі \(current).", level: .success)
                    break
                }
            }
            let training = clock.now - trainingStart
            trainingTime = training

            // 3. Evaluation and activation of the new model.
            phase = .evaluating
            let predictions = try await engine.testPredictions()
            var confusion = Array(repeating: Array(repeating: 0, count: 3), count: 3)
            var wrong: [MisclassifiedImage] = []
            for (sample, predicted) in zip(test, predictions) {
                confusion[sample.image.classIndex][predicted] += 1
                if predicted != sample.image.classIndex {
                    wrong.append(MisclassifiedImage(url: sample.image.url, expected: sample.image.classIndex, predicted: predicted))
                }
            }
            let model = try await engine.modelJSON()
            let bundledAccuracy = Self.accuracy(of: try? FigureRecognizer.bundledNetwork(), on: test)
            resultApplied = false

            let finished = TrainingResult(
                config: config, groups: groups, trainCount: train.count, testCount: test.count, workers: workers,
                epochsDone: epoch, finalError: lastError,
                trainAccuracy: try await engine.accuracy(test: false),
                testAccuracy: try await engine.accuracy(test: true),
                confusion: confusion, misclassified: wrong,
                extractionTime: extraction, trainingTime: training, totalTime: clock.now - started,
                modelJSON: model,
                bundledTestAccuracy: bundledAccuracy
            )
            result = finished
            phase = .finished
            log.add(String(format: "Навчання завершено за %@: точність train %.2f %%, test %.2f %% (вбудована модель на цих же тестових: %.2f %%).",
                           finished.totalTime.formattedSeconds, finished.trainAccuracy * 100, finished.testAccuracy * 100,
                           (bundledAccuracy ?? 0) * 100), level: .success)
        } catch is CancellationError {
            phase = .cancelled
            log.add("Навчання зупинено на епосі \(epoch).", level: .warning)
        } catch {
            phase = .failed(error.localizedDescription)
            log.add("Помилка навчання: \(error.localizedDescription)", level: .error)
        }
        phaseStartedAt = nil
        endedAt = .now
    }

    /// The trained model replaces the bundled one only on the user's request.
    func applyTrainedModel() async {
        guard let result else { return }
        do {
            try await FigureRecognizer.shared.install(trainedModel: result.modelJSON)
            usesTrainedModel = true
            resultApplied = true
            log.add(String(format: "Активовано модель, навчену в застосунку (test %.2f %%).", result.testAccuracy * 100), level: .success)
        } catch {
            log.add("Не вдалося активувати модель: \(error.localizedDescription)", level: .error)
        }
    }

    private nonisolated static func accuracy(of network: BrainNetwork?, on samples: [ExtractedSample]) -> Double? {
        guard let network, !samples.isEmpty else { return nil }
        let right = samples.filter { sample in
            let outputs = network.run(sample.features)
            return outputs.indices.max { outputs[$0] < outputs[$1] } == sample.image.classIndex
        }.count
        return Double(right) / Double(samples.count)
    }

    /// Same images processed with one worker and with one worker per core.
    func runBenchmark() async {
        guard !isBenchmarking, !isRunning else { return }
        isBenchmarking = true
        defer { isBenchmarking = false }
        let images = Array(TrainingDataset.images(in: groups).prefix(imageLimit))
        let cores = ParallelFeatureExtractor.coreCount
        benchmarkTotal = images.count * 2
        benchmarkProcessed = 0
        log.add("Бенчмарк обробки: \(images.count) зображень, 1 потік проти \(cores).")
        let clock = ContinuousClock()
        do {
            let sequentialStart = clock.now
            _ = try await ParallelFeatureExtractor.extract(images, workers: 1) { done, _ in
                await MainActor.run { self.benchmarkProcessed = done }
            }
            let sequential = clock.now - sequentialStart
            let parallelStart = clock.now
            _ = try await ParallelFeatureExtractor.extract(images, workers: cores) { done, _ in
                await MainActor.run { self.benchmarkProcessed = images.count + done }
            }
            let parallel = clock.now - parallelStart
            benchmark = BenchmarkResult(images: images.count, sequential: sequential, parallel: parallel, workers: cores)
            log.add(String(format: "Бенчмарк: 1 потік %@, %d потоків %@, прискорення ×%.2f.",
                           sequential.formattedSeconds, cores, parallel.formattedSeconds, sequential / parallel), level: .success)
        } catch {
            log.add("Бенчмарк перервано: \(error.localizedDescription)", level: .error)
        }
    }

    /// Writes the trained model and the run report to a temporary folder for sharing.
    func exportFiles() -> [URL] {
        guard let result else { return [] }
        let folder = URL.temporaryDirectory.appending(path: "training-\(Int(Date.now.timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []

        let modelURL = folder.appending(path: "model.json")
        if (try? result.modelJSON.write(to: modelURL)) != nil { urls.append(modelURL) }

        var csv = "epoch,error,train_accuracy,test_accuracy\n"
        for point in history {
            csv += "\(point.epoch),\(point.error),\(point.trainAccuracy.map { String($0) } ?? ""),\(point.testAccuracy.map { String($0) } ?? "")\n"
        }
        let csvURL = folder.appending(path: "training-history.csv")
        if (try? csv.write(to: csvURL, atomically: true, encoding: .utf8)) != nil { urls.append(csvURL) }

        let summary: [String: Any] = [
            "groups": result.groups.map(\.rawValue),
            "trainImages": result.trainCount, "testImages": result.testCount,
            "epochs": result.config.epochs, "epochsDone": result.epochsDone,
            "learningRate": result.config.learningRate, "momentum": result.config.momentum,
            "hiddenNeurons": result.config.hiddenNeurons, "errorThresh": result.config.errorThresh,
            "workers": result.workers, "finalError": result.finalError,
            "trainAccuracy": result.trainAccuracy, "testAccuracy": result.testAccuracy,
            "confusion": result.confusion,
            "extractionSeconds": result.extractionTime.seconds, "trainingSeconds": result.trainingTime.seconds,
            "totalSeconds": result.totalTime.seconds
        ]
        let summaryURL = folder.appending(path: "training-summary.json")
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]),
           (try? data.write(to: summaryURL)) != nil { urls.append(summaryURL) }

        log.add("Експортовано результати навчання: \(urls.map(\.lastPathComponent).joined(separator: ", ")).", level: .success)
        return urls
    }
}

nonisolated extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    var formattedSeconds: String {
        String(format: "%.2f с", seconds)
    }
}
