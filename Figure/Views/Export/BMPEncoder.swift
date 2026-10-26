import CoreGraphics
import Foundation

/// 24-bit uncompressed BMP writer. UIKit encodes PNG and JPEG itself, but has no BMP output,
/// and the format is simple enough that a writer is cheaper than an extra dependency.
nonisolated enum BMPEncoder {
    private static let fileHeaderSize = 14
    private static let infoHeaderSize = 40
    private static let pixelsPerMetre: Int32 = 2835 // ~72 dpi

    static func encode(_ image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return false }

            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Every BMP row is padded to a multiple of four bytes.
        let rowSize = ((width * 3 + 3) / 4) * 4
        let pixelDataSize = rowSize * height
        let fileSize = fileHeaderSize + infoHeaderSize + pixelDataSize

        var data = Data(capacity: fileSize)
        data.append(contentsOf: [0x42, 0x4D]) // "BM"
        data.appendLittleEndian(UInt32(fileSize))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt32(fileHeaderSize + infoHeaderSize))

        data.appendLittleEndian(UInt32(infoHeaderSize))
        data.appendLittleEndian(Int32(width))
        data.appendLittleEndian(Int32(height))
        data.appendLittleEndian(UInt16(1))  // colour planes
        data.appendLittleEndian(UInt16(24)) // bits per pixel
        data.appendLittleEndian(UInt32(0))  // BI_RGB, no compression
        data.appendLittleEndian(UInt32(pixelDataSize))
        data.appendLittleEndian(pixelsPerMetre)
        data.appendLittleEndian(pixelsPerMetre)
        data.appendLittleEndian(UInt32(0))  // colours in palette
        data.appendLittleEndian(UInt32(0))  // important colours

        // BMP stores rows bottom-up and channels as BGR.
        var row = [UInt8](repeating: 0, count: rowSize)
        for y in stride(from: height - 1, through: 0, by: -1) {
            for index in row.indices {
                row[index] = 0
            }
            for x in 0..<width {
                let source = (y * width + x) * 4
                let target = x * 3
                row[target] = rgba[source + 2]
                row[target + 1] = rgba[source + 1]
                row[target + 2] = rgba[source]
            }
            data.append(contentsOf: row)
        }

        return data
    }
}

nonisolated private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &little) { Array($0) })
    }
}
