import SwiftUI

enum FigureClass: String, CaseIterable, Codable, Hashable, Identifiable {
    case circle
    case square
    case triangle

    var id: Self { self }

    var title: String {
        switch self {
        case .circle: "Коло"
        case .square: "Квадрат"
        case .triangle: "Трикутник"
        }
    }

    var tint: Color {
        switch self {
        case .circle: Color(red: 0.949, green: 0.933, blue: 1.000)
        case .square: Color(red: 0.918, green: 0.957, blue: 1.000)
        case .triangle: Color(red: 1.000, green: 0.945, blue: 0.910)
        }
    }

    var selectedTint: Color {
        switch self {
        case .circle: Color(red: 0.910, green: 0.882, blue: 1.000)
        case .square: Color(red: 0.863, green: 0.922, blue: 1.000)
        case .triangle: Color(red: 1.000, green: 0.894, blue: 0.831)
        }
    }

    var iconColor: Color {
        switch self {
        case .circle: Color(red: 0.412, green: 0.341, blue: 0.851)
        case .square: Color(red: 0.204, green: 0.471, blue: 0.788)
        case .triangle: Color(red: 0.851, green: 0.416, blue: 0.235)
        }
    }
}

