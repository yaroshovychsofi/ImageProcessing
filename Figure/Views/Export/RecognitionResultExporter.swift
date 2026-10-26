import SwiftUI

@MainActor
enum RecognitionResultExporter {
    static func makeData(for record: RecognitionRecord, format: ExportFormat) -> Data? {
        let renderer = ImageRenderer(content: RecognitionExportCard(record: record))
        renderer.scale = 3

        switch format {
        case .png:
            return renderer.uiImage?.pngData()
        case .jpeg:
            return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        case .bmp:
            return renderer.cgImage.flatMap(BMPEncoder.encode)
        }
    }

    static func defaultFileName(for record: RecognitionRecord) -> String {
        "Результат-\(record.predictedClass.title)"
    }
}
