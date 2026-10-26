import Foundation

enum InputMode: String, CaseIterable, Identifiable {
    case original = "Оригінал"
    case networkInput = "Вхід мережі"

    var id: Self { self }
}

