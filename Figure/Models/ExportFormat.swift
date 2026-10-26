import UniformTypeIdentifiers

nonisolated enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case bmp

    var id: Self { self }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .bmp: "BMP"
        }
    }

    var subtitle: String {
        switch self {
        case .png: "без втрат, прозорість"
        case .jpeg: "менший розмір"
        case .bmp: "без стиснення"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .bmp: .bmp
        }
    }
}
