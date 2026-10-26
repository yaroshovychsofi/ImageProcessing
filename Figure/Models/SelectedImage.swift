import Foundation

struct SelectedImage: Identifiable, Equatable, Codable {
    let id: UUID
    let imageData: Data?
    let sample: FigureClass?
    let fileName: String
    let format: String
    let resolution: String
    let size: String
    let colorSpace: String
    let selectedAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        sample: FigureClass? = nil,
        fileName: String,
        format: String,
        resolution: String,
        size: String,
        colorSpace: String = "sRGB",
        selectedAt: Date = .now
    ) {
        self.id = id
        self.imageData = imageData
        self.sample = sample
        self.fileName = fileName
        self.format = format
        self.resolution = resolution
        self.size = size
        self.colorSpace = colorSpace
        self.selectedAt = selectedAt
    }

    static func sample(_ figure: FigureClass) -> Self {
        Self(
            sample: figure,
            fileName: "\(figure.rawValue).png",
            format: "PNG",
            resolution: "512 × 512 px",
            size: "46 KB"
        )
    }
}
