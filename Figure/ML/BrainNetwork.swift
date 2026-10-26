import Foundation

nonisolated enum BrainNetworkError: LocalizedError {
    case modelMissing
    case unsupportedActivation(String)
    case malformedModel(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "Файл навченої моделі не знайдено в застосунку."
        case .unsupportedActivation(let name):
            "Модель використовує функцію активації «\(name)», яка не підтримується."
        case .malformedModel(let reason):
            "Не вдалося прочитати модель: \(reason)."
        }
    }
}

/// Forward pass over a network serialised by `brain.NeuralNetwork#toJSON()`.
/// Training happens only in `Tools/Trainer` (Brain.js); the app evaluates the result.
/// Brain.js applies a sigmoid to every layer including the output one, so the three outputs
/// are independent activations that do not sum to 1. `calibratedProbabilities` turns them into
/// a calibrated distribution for display.
nonisolated struct BrainNetwork: Sendable {
    struct Layer: Sendable {
        let weights: [[Double]]
        let biases: [Double]
    }

    let sizes: [Int]
    let layers: [Layer]

    var inputSize: Int { sizes.first ?? 0 }

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode(SerialisedNetwork.self, from: data)

        if let activation = decoded.options?.activation, activation != "sigmoid" {
            throw BrainNetworkError.unsupportedActivation(activation)
        }

        let trainable = decoded.layers.compactMap { layer -> Layer? in
            guard let weights = layer.weights, let biases = layer.biases,
                  !weights.isEmpty, weights.count == biases.count
            else { return nil }
            return Layer(weights: weights, biases: biases)
        }

        guard !trainable.isEmpty else {
            throw BrainNetworkError.malformedModel("модель не містить шарів з вагами")
        }
        guard let sizes = decoded.sizes, sizes.count == trainable.count + 1 else {
            throw BrainNetworkError.malformedModel("розміри шарів не узгоджені")
        }
        for (index, layer) in trainable.enumerated() {
            guard layer.weights.allSatisfy({ $0.count == sizes[index] }) else {
                throw BrainNetworkError.malformedModel("шар \(index + 1) очікує \(sizes[index]) входів")
            }
        }

        self.sizes = sizes
        self.layers = trainable
    }

    func run(_ input: [Double]) -> [Double] {
        var activations = input

        for layer in layers {
            var next = [Double](repeating: 0, count: layer.biases.count)
            for neuron in 0..<layer.biases.count {
                var sum = layer.biases[neuron]
                let weights = layer.weights[neuron]
                for index in 0..<activations.count {
                    sum += weights[index] * activations[index]
                }
                next[neuron] = 1 / (1 + exp(-sum))
            }
            activations = next
        }

        return activations
    }

    /// Converts independent sigmoid activations into calibrated class probabilities.
    /// Temperature scaling preserves the winning class while preventing saturated outputs
    /// from being presented as certainty.
    static func calibratedProbabilities(from outputs: [Double], temperature: Double) -> [Double] {
        guard !outputs.isEmpty else { return [] }
        let safeTemperature = temperature.isFinite && temperature > 0 ? temperature : 1
        let logits = outputs.map { value in
            let probability = min(1 - 1e-12, max(1e-12, value))
            return log(probability / (1 - probability)) / safeTemperature
        }
        let largest = logits.max() ?? 0
        let exponentials = logits.map { exp($0 - largest) }
        let total = exponentials.reduce(0, +)
        return total > 0
            ? exponentials.map { $0 / total }
            : exponentials.map { _ in 1 / Double(exponentials.count) }
    }
}

nonisolated private struct SerialisedNetwork: Decodable {
    struct Layer: Decodable {
        let weights: [[Double]]?
        let biases: [Double]?
    }

    struct Options: Decodable {
        let activation: String?
    }

    let sizes: [Int]?
    let layers: [Layer]
    let options: Options?
}
