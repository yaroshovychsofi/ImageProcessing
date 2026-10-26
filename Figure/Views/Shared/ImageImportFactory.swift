import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ImageImportFactory {
    /// The picker hands over raw bytes without a usable name, and a file's extension can
    /// disagree with its contents, so the format is read from the data itself. An iPhone photo
    /// is HEIC by default — labelling it "JPG" would make the file info panel lie.
    static func detectFormat(from data: Data) -> (name: String, fileExtension: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier)
        else { return nil }

        let fileExtension = type.preferredFilenameExtension ?? "img"
        return (fileExtension.uppercased(), fileExtension)
    }

    /// Read from the file's own metadata: a grayscale PNG is not sRGB, and claiming otherwise
    /// in the info panel is as wrong as mislabelling the format.
    static func detectColorSpace(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        if let profile = properties[kCGImagePropertyProfileName] as? String {
            return profile
        }

        guard let model = properties[kCGImagePropertyColorModel] as? String else { return nil }

        let names: [String: String] = [
            String(kCGImagePropertyColorModelGray): "Grayscale",
            String(kCGImagePropertyColorModelRGB): "RGB",
            String(kCGImagePropertyColorModelCMYK): "CMYK"
        ]
        return names[model] ?? model
    }

    static func makeImage(data: Data, fileName: String, format: String) -> SelectedImage? {
        guard let image = UIImage(data: data) else { return nil }

        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)

        return SelectedImage(
            imageData: data,
            fileName: fileName,
            format: format.uppercased(),
            resolution: "\(width) × \(height) px",
            size: size,
            colorSpace: detectColorSpace(from: data) ?? "Невідомо"
        )
    }

    /// Used for the photo library, where only the bytes are available.
    static func makeImage(data: Data) -> SelectedImage? {
        let detected = detectFormat(from: data)
        return makeImage(
            data: data,
            fileName: "Фото.\(detected?.fileExtension ?? "img")",
            format: detected?.name ?? "IMAGE"
        )
    }
}
