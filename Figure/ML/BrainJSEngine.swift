import Foundation
import JavaScriptCore

nonisolated struct TrainingConfig: Sendable, Codable, Equatable {
    var epochs = 200
    var learningRate = 0.3
    var momentum = 0.1
    var hiddenNeurons = 8
    var errorThresh = 0.005
    /// Accuracy on both splits is measured every `evaluateEvery` epochs for the chart.
    var evaluateEvery = 5
}

nonisolated enum BrainJSError: LocalizedError {
    case libraryMissing
    case script(String)

    var errorDescription: String? {
        switch self {
        case .libraryMissing: "Бібліотеку Brain.js не знайдено в застосунку."
        case .script(let message): "Помилка Brain.js: \(message)"
        }
    }
}

/// Runs the real Brain.js library (`brain-browser.js`, the same build as in `Tools/Trainer`)
/// inside JavaScriptCore. Training is gradient descent where each epoch depends on the weights
/// of the previous one, so it cannot be parallelised across epochs; the actor keeps it off the
/// main thread and lets the caller step it one epoch at a time to report progress and stop.
actor BrainJSEngine {
    private var context: JSContext?

    func prepare(train: [ExtractedSample], test: [ExtractedSample], config: TrainingConfig) throws {
        let context = try makeContext()
        context.setObject(try Self.json(train), forKeyedSubscript: "trainJSON" as NSString)
        context.setObject(try Self.json(test), forKeyedSubscript: "testJSON" as NSString)
        try run("""
            var trainData = JSON.parse(trainJSON);
            var testData = JSON.parse(testJSON);
            var net = new brain.NeuralNetwork({ hiddenLayers: [\(config.hiddenNeurons)], activation: 'sigmoid' });
            function argmax(values) {
                var best = 0;
                for (var i = 1; i < values.length; i++) if (values[i] > values[best]) best = i;
                return best;
            }
            function predictions(data) {
                return data.map(function (item) { return argmax(Array.from(net.run(item.input))); });
            }
            function accuracy(data) {
                if (data.length === 0) return 0;
                var right = 0;
                predictions(data).forEach(function (p, i) { if (data[i].output[p] === 1) right++; });
                return right / data.length;
            }
            """, in: context)
        self.context = context
    }

    /// One pass of Brain.js over the training set. Returns the mean squared training error.
    func trainEpoch(_ epoch: Int, config: TrainingConfig) throws -> Double {
        guard let context else { throw BrainJSError.script("мережу не підготовлено") }
        let value = try run("""
            net.train(trainData, {
                iterations: 1,
                learningRate: \(config.learningRate),
                momentum: \(config.momentum),
                errorThresh: 1e-12,
                log: false,
                keepNetworkIntact: \(epoch > 1)
            }).error
            """, in: context)
        return value.toDouble()
    }

    func accuracy(test: Bool) throws -> Double {
        guard let context else { return 0 }
        return try run("accuracy(\(test ? "testData" : "trainData"))", in: context).toDouble()
    }

    func testPredictions() throws -> [Int] {
        guard let context else { return [] }
        let value = try run("JSON.stringify(predictions(testData))", in: context).toString() ?? "[]"
        return (try? JSONDecoder().decode([Int].self, from: Data(value.utf8))) ?? []
    }

    /// `net.toJSON()` — the same format the Node trainer writes to `model.json`.
    func modelJSON() throws -> Data {
        guard let context else { throw BrainJSError.script("мережу не навчено") }
        let text = try run("JSON.stringify(net.toJSON())", in: context).toString() ?? ""
        return Data(text.utf8)
    }

    private func makeContext() throws -> JSContext {
        guard let url = Bundle.main.url(forResource: "brain-browser", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext()
        else { throw BrainJSError.libraryMissing }
        context.evaluateScript("var self = this; var window = this;")
        context.evaluateScript(source, withSourceURL: url)
        if context.objectForKeyedSubscript("brain").isUndefined {
            throw BrainJSError.libraryMissing
        }
        return context
    }

    @discardableResult
    private func run(_ script: String, in context: JSContext) throws -> JSValue {
        context.exception = nil
        let value = context.evaluateScript(script)
        if let exception = context.exception {
            context.exception = nil
            throw BrainJSError.script(exception.toString() ?? "невідома помилка")
        }
        return value ?? JSValue(undefinedIn: context)
    }

    private static func json(_ samples: [ExtractedSample]) throws -> String {
        struct Item: Encodable { let input: [Double]; let output: [Int] }
        let items = samples.map { sample in
            Item(input: sample.features, output: (0..<3).map { $0 == sample.image.classIndex ? 1 : 0 })
        }
        return String(decoding: try JSONEncoder().encode(items), as: UTF8.self)
    }
}
