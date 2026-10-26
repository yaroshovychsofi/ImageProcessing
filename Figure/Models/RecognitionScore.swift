import Foundation

struct RecognitionScore: Identifiable, Hashable, Codable, Sendable {
    let figure: FigureClass
    let confidence: Double

    var id: FigureClass { figure }
}
