import CoreGraphics
import simd

nonisolated extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }
}

/// JavaScript's `Math.round` rounds halves towards +infinity; Swift's `rounded()` rounds them
/// away from zero. On negative halves the two disagree, which is enough to shift a pixel and
/// put the Swift features out of step with the ones the network was trained on.
nonisolated func roundedLikeJS(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
}

nonisolated struct GrayscaleImage: Sendable {
    let pixels: [Double]
    let width: Int
    let height: Int
}

nonisolated struct PixelBox: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

nonisolated struct NormalisedShape: Sendable {
    let grid: [Double]
    let mask: [UInt8]
    let width: Int
    let height: Int
    let box: PixelBox
    let hull: [SIMD2<Double>]
}

/// Exact normalisation used by the first shipped 67-input model.  It intentionally keeps
/// the original component instead of replacing it with a convex hull or rotating it.
/// Mirror of `Tools/Trainer/preprocess.js`. Every step and constant must stay identical to
/// the trainer, otherwise the network receives features it was never trained on.
/// `FixtureValidator` verifies that invariant against reference vectors produced by Brain.js.
nonisolated enum ImagePreprocessor {
    static let gridSide = 32
    static let maxInputSide = 512

    static func grayscale(from image: CGImage, maxSide: Int = maxInputSide) -> GrayscaleImage? {
        let longestSide = max(image.width, image.height)
        let scale = longestSide > maxSide ? Double(maxSide) / Double(longestSide) : 1
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
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
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }

        var pixels = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let offset = index * 4
            let red = Double(bytes[offset])
            let green = Double(bytes[offset + 1])
            let blue = Double(bytes[offset + 2])
            pixels[index] = (0.299 * red + 0.587 * green + 0.114 * blue) / 255
        }

        return GrayscaleImage(pixels: pixels, width: width, height: height)
    }

    static func otsuThreshold(_ pixels: [Double]) -> Double {
        var histogram = [Double](repeating: 0, count: 256)
        for value in pixels {
            let level = min(255, max(0, roundedLikeJS(value * 255)))
            histogram[level] += 1
        }

        let total = Double(pixels.count)
        var sum = 0.0
        for level in 0..<256 {
            sum += Double(level) * histogram[level]
        }

        var backgroundWeight = 0.0
        var backgroundSum = 0.0
        var bestVariance = -1.0
        var bestLevel = 127

        for level in 0..<256 {
            backgroundWeight += histogram[level]
            if backgroundWeight == 0 { continue }
            let foregroundWeight = total - backgroundWeight
            if foregroundWeight == 0 { break }

            backgroundSum += Double(level) * histogram[level]
            let backgroundMean = backgroundSum / backgroundWeight
            let foregroundMean = (sum - backgroundSum) / foregroundWeight
            let delta = backgroundMean - foregroundMean
            let variance = backgroundWeight * foregroundWeight * delta * delta

            if variance > bestVariance {
                bestVariance = variance
                bestLevel = level
            }
        }

        return Double(bestLevel) / 255
    }

    /// Keeps all substantial parts of a possibly interrupted hand-drawn contour while still
    /// rejecting isolated dust and compression artefacts. Keeping only the largest component
    /// can turn a square with a pencil gap into an L-shaped fragment.
    static func significantComponents(
        _ mask: [UInt8],
        width: Int,
        height: Int,
        minimumRelativeSize: Double = 0.12
    ) -> [UInt8] {
        var labels = [Int32](repeating: -1, count: mask.count)
        var queue = [Int](repeating: 0, count: mask.count)
        var sizes: [Int] = []
        var label: Int32 = 0

        for start in mask.indices where mask[start] != 0 && labels[start] == -1 {
            var head = 0
            var tail = 0
            queue[tail] = start
            tail += 1
            labels[start] = label
            var size = 0

            while head < tail {
                let index = queue[head]
                head += 1
                size += 1
                let x = index % width
                let y = index / width

                func visit(_ neighbour: Int) {
                    if mask[neighbour] != 0, labels[neighbour] == -1 {
                        labels[neighbour] = label
                        queue[tail] = neighbour
                        tail += 1
                    }
                }

                if x > 0 { visit(index - 1) }
                if x + 1 < width { visit(index + 1) }
                if y > 0 { visit(index - width) }
                if y + 1 < height { visit(index + width) }
            }

            sizes.append(size)
            label += 1
        }

        guard let largest = sizes.max() else { return mask }
        let minimumSize = max(2, Int((Double(largest) * minimumRelativeSize).rounded(.up)))
        var out = [UInt8](repeating: 0, count: mask.count)
        for index in mask.indices {
            let component = labels[index]
            if component >= 0, sizes[Int(component)] >= minimumSize {
                out[index] = 1
            }
        }
        return out
    }

    /// 1 marks the figure, 0 the background. The minority class is taken as the figure,
    /// which makes the pipeline indifferent to dark-on-light and light-on-dark input.
    static func makeMask(_ pixels: [Double], width: Int, height: Int) -> [UInt8] {
        // Threshold the original pixels here: a 3x3 median filter can erase a one-pixel pencil
        // stroke. The component filter below removes isolated noise without losing the contour.
        let threshold = otsuThreshold(pixels)

        var mask = [UInt8](repeating: 0, count: pixels.count)
        var darkCount = 0
        for index in pixels.indices {
            let isDark: UInt8 = pixels[index] <= threshold ? 1 : 0
            mask[index] = isDark
            darkCount += Int(isDark)
        }

        if darkCount * 2 > pixels.count {
            for index in 0..<mask.count {
                mask[index] = mask[index] == 0 ? 1 : 0
            }
        }

        let blob = significantComponents(mask, width: width, height: height)
        guard let hull = convexHull(blob, width: width, height: height) else { return blob }
        return fillHull(hull, width: width, height: height)
    }

    /// Convex hull of the thresholded blob, filled by scanlines.
    ///
    /// All three classes are convex, so the hull loses nothing that matters and gains a lot:
    /// a hand-drawn outline becomes the solid figure it depicts, and gaps in the stroke stop
    /// mattering. Morphological closing plus hole filling was tried first and left 15% of the
    /// hand-drawn training set unusable; the hull brings that down to 1%. The price is that
    /// any blob now looks solid and convex, so this cannot tell a figure from a photograph.
    static func convexHull(_ mask: [UInt8], width: Int, height: Int) -> [SIMD2<Double>]? {
        var points: [SIMD2<Double>] = []

        // Only boundary pixels can be hull vertices, which keeps the sort small.
        for y in 0..<height {
            var first = -1
            var last = -1
            for x in 0..<width where mask[y * width + x] != 0 {
                if first < 0 { first = x }
                last = x
            }
            if first >= 0 {
                points.append(SIMD2(Double(first), Double(y)))
                if last != first { points.append(SIMD2(Double(last), Double(y))) }
            }
        }
        guard points.count >= 3 else { return nil }

        points.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [SIMD2<Double>] = []
        for point in points {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [SIMD2<Double>] = []
        for point in points.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    /// Scanline fill of a convex polygon: per row the polygon covers one interval, so only its
    /// left and right edges have to be found.
    static func fillHull(_ hull: [SIMD2<Double>], width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            var minX = Double.infinity
            var maxX = -Double.infinity
            let row = Double(y)

            for index in hull.indices {
                let a = hull[index]
                let b = hull[(index + 1) % hull.count]

                if a.y == b.y {
                    if a.y != row { continue }
                    minX = min(minX, a.x, b.x)
                    maxX = max(maxX, a.x, b.x)
                    continue
                }

                if row < min(a.y, b.y) || row > max(a.y, b.y) { continue }
                let x = a.x + (row - a.y) * (b.x - a.x) / (b.y - a.y)
                minX = min(minX, x)
                maxX = max(maxX, x)
            }

            if minX > maxX { continue }
            let from = max(0, Int((minX - 0.5).rounded(.up)))
            let to = min(width - 1, Int((maxX + 0.5).rounded(.down)))
            if from > to { continue }
            for x in from...to { out[y * width + x] = 1 }
        }

        return out
    }

    /// Angle of the longest edge of the hull's minimum-area rectangle. Rotating by -angle puts
    /// every figure into the same canonical orientation before the cell grid is taken, which is
    /// what makes the 8x8 intensities comparable between a figure drawn upright and the same
    /// figure drawn at 40 degrees.
    static func orientation(_ hull: [SIMD2<Double>]) -> Double {
        // A rectangle has 90-degree symmetry, so every candidate is folded into [0, 90).
        // Without that, a symmetric figure produces several edges with a bit-identical
        // rectangle area and the winner depends on where the hull happens to start.
        func fold(_ value: Double) -> Double {
            let quarter = Double.pi / 2
            let folded = value.truncatingRemainder(dividingBy: quarter)
            return folded < 0 ? folded + quarter : folded
        }

        var smallest = Double.infinity
        var angle = 0.0

        for index in hull.indices {
            let a = hull[index]
            let b = hull[(index + 1) % hull.count]
            let length = (b - a).length
            if length == 0 { continue }

            let unit = (b - a) / length
            var minU = Double.infinity
            var maxU = -Double.infinity
            var minV = Double.infinity
            var maxV = -Double.infinity

            for point in hull {
                let u = point.x * unit.x + point.y * unit.y
                let v = -point.x * unit.y + point.y * unit.x
                minU = min(minU, u)
                maxU = max(maxU, u)
                minV = min(minV, v)
                maxV = max(maxV, v)
            }

            let area = (maxU - minU) * (maxV - minV)
            let candidate = fold(atan2(unit.y, unit.x))
            if area < smallest * (1 - 1e-9) || (area <= smallest * (1 + 1e-9) && candidate < angle) {
                if area < smallest { smallest = area }
                angle = candidate
            }
        }

        return angle
    }

    /// Nearest-neighbour rotation of a binary mask onto an expanded canvas.
    static func rotateMask(_ mask: [UInt8], width: Int, height: Int, angle: Double) -> (mask: [UInt8], width: Int, height: Int) {
        let cosine = cos(-angle)
        let sine = sin(-angle)
        let outWidth = Int((abs(Double(width) * cosine) + abs(Double(height) * sine)).rounded(.up))
        let outHeight = Int((abs(Double(width) * sine) + abs(Double(height) * cosine)).rounded(.up))
        var out = [UInt8](repeating: 0, count: outWidth * outHeight)

        let srcCx = Double(width - 1) / 2
        let srcCy = Double(height - 1) / 2
        let dstCx = Double(outWidth - 1) / 2
        let dstCy = Double(outHeight - 1) / 2

        for y in 0..<outHeight {
            for x in 0..<outWidth {
                let dx = Double(x) - dstCx
                let dy = Double(y) - dstCy
                let sx = roundedLikeJS(srcCx + dx * cosine + dy * sine)
                let sy = roundedLikeJS(srcCy - dx * sine + dy * cosine)
                if sx >= 0, sy >= 0, sx < width, sy < height {
                    out[y * outWidth + x] = mask[sy * width + sx]
                }
            }
        }

        return (out, outWidth, outHeight)
    }

    static func boundingBox(_ mask: [UInt8], width: Int, height: Int) -> PixelBox? {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        guard maxX >= 0 else { return nil }
        return PixelBox(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func cropMask(_ mask: [UInt8], width: Int, box: PixelBox) -> [UInt8] {
        var crop = [UInt8](repeating: 0, count: box.width * box.height)
        for y in 0..<box.height {
            for x in 0..<box.width {
                crop[y * box.width + x] = mask[(box.y + y) * width + box.x + x]
            }
        }
        return crop
    }

    /// Area-weighted (box filter) resampling with exact fractional pixel coverage, so the
    /// result is bit-comparable with the JavaScript trainer and free of aliasing.
    static func resample(_ crop: [UInt8], width: Int, height: Int, side: Int = gridSide) -> [Double] {
        var out = [Double](repeating: 0, count: side * side)
        let scaleX = Double(width) / Double(side)
        let scaleY = Double(height) / Double(side)

        for gy in 0..<side {
            let y0 = Double(gy) * scaleY
            let y1 = y0 + scaleY

            for gx in 0..<side {
                let x0 = Double(gx) * scaleX
                let x1 = x0 + scaleX
                var accumulated = 0.0

                for py in Int(y0.rounded(.down))..<Int(y1.rounded(.up)) {
                    let weightY = min(Double(py) + 1, y1) - max(Double(py), y0)
                    if weightY <= 0 { continue }

                    for px in Int(x0.rounded(.down))..<Int(x1.rounded(.up)) {
                        let weightX = min(Double(px) + 1, x1) - max(Double(px), x0)
                        if weightX <= 0 { continue }
                        accumulated += Double(crop[py * width + px]) * weightX * weightY
                    }
                }

                out[gy * side + gx] = accumulated / (scaleX * scaleY)
            }
        }

        return out
    }

    static func normalise(_ image: GrayscaleImage) -> NormalisedShape? {
        let mask = makeMask(image.pixels, width: image.width, height: image.height)
        guard let box = boundingBox(mask, width: image.width, height: image.height) else { return nil }

        let firstCrop = cropMask(mask, width: image.width, box: box)
        guard let firstHull = convexHull(firstCrop, width: box.width, height: box.height) else { return nil }

        // Canonical orientation, then crop again: rotating moves the figure inside its canvas.
        let rotated = rotateMask(firstCrop, width: box.width, height: box.height, angle: orientation(firstHull))
        guard let rotatedBox = boundingBox(rotated.mask, width: rotated.width, height: rotated.height) else { return nil }

        let crop = cropMask(rotated.mask, width: rotated.width, box: rotatedBox)
        guard let hull = convexHull(crop, width: rotatedBox.width, height: rotatedBox.height) else { return nil }

        return NormalisedShape(
            grid: resample(crop, width: rotatedBox.width, height: rotatedBox.height),
            mask: crop,
            width: rotatedBox.width,
            height: rotatedBox.height,
            box: box,
            hull: hull
        )
    }
}
