import Foundation

struct RecognitionRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let image: SelectedImage
    let predictedClass: FigureClass
    let confidence: Double
    let createdAt: Date
    /// Normalised network outputs, sorted from the most to the least probable class.
    let scores: [RecognitionScore]
    /// The 8x8 cell intensities the network actually received.
    let networkInput: [Double]
    let durationMilliseconds: Double
    /// `nil` for records saved before the app could train its own model.
    let usedTrainedModel: Bool?

    var modelTitle: String {
        usedTrainedModel == true ? "Модель, навчена в застосунку" : "Вбудована модель"
    }

    init(
        id: UUID = UUID(),
        image: SelectedImage,
        predictedClass: FigureClass,
        confidence: Double,
        createdAt: Date = .now,
        scores: [RecognitionScore],
        networkInput: [Double] = [],
        durationMilliseconds: Double = 0,
        usedTrainedModel: Bool? = nil
    ) {
        self.id = id
        self.image = image
        self.predictedClass = predictedClass
        self.confidence = confidence
        self.createdAt = createdAt
        self.scores = scores
        self.networkInput = networkInput
        self.durationMilliseconds = durationMilliseconds
        self.usedTrainedModel = usedTrainedModel
    }

    /// Records cached before the network was wired in stored only a predicted class and its
    /// confidence, so their distribution is reconstructed the way the interface used to show it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        image = try container.decode(SelectedImage.self, forKey: .image)
        predictedClass = try container.decode(FigureClass.self, forKey: .predictedClass)
        confidence = try container.decode(Double.self, forKey: .confidence)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        networkInput = try container.decodeIfPresent([Double].self, forKey: .networkInput) ?? []
        durationMilliseconds = try container.decodeIfPresent(Double.self, forKey: .durationMilliseconds) ?? 0
        usedTrainedModel = try container.decodeIfPresent(Bool.self, forKey: .usedTrainedModel)
        scores = try container.decodeIfPresent([RecognitionScore].self, forKey: .scores)
            ?? Self.estimatedScores(predictedClass: predictedClass, confidence: confidence)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var shareText: String {
        let distribution = scores
            .map { score in
                "\(score.figure.title) — \(ConfidenceText.percent(score.confidence))"
            }
            .joined(separator: ", ")

        return "Результат розпізнавання: \(predictedClass.title), впевненість — \(ConfidenceText.percent(confidence)). Розподіл: \(distribution)."
    }

    private static func estimatedScores(predictedClass: FigureClass, confidence: Double) -> [RecognitionScore] {
        let otherClasses: [FigureClass]
        switch predictedClass {
        case .triangle:
            otherClasses = [.square, .circle]
        case .square:
            otherClasses = [.triangle, .circle]
        case .circle:
            otherClasses = [.square, .triangle]
        }

        let remainder = max(0, 1 - confidence)
        return [
            RecognitionScore(figure: predictedClass, confidence: confidence),
            RecognitionScore(figure: otherClasses[0], confidence: remainder * 2 / 3),
            RecognitionScore(figure: otherClasses[1], confidence: remainder / 3)
        ]
    }
}
