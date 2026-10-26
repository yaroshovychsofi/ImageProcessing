import Foundation
import simd

nonisolated struct ShapeGeometry: Sendable {
    let fill: Double
    let compactness: Double
    let symmetry: Double
    let corners: Int
    let rectangularity: Double
}

nonisolated struct FigureFeatures: Sendable {
    let values: [Double]
    let cells: [Double]
    let geometry: ShapeGeometry
}

/// Mirror of `Tools/Trainer/features.js`: classification by cell intensities (the second
/// method from the Zavyalov article) plus three scale-invariant geometric descriptors,
/// because an 8x8 grid alone cannot separate a square rotated by 45 degrees from a triangle.
nonisolated enum FeatureExtractor {
    static let cells = 8
    static let pool = ImagePreprocessor.gridSide / 8
    static let gridFeatures = 64
    static let featureCount = 69
    static let maxCorners = 12

    static func poolGrid(_ grid: [Double]) -> [Double] {
        var pooled = [Double](repeating: 0, count: gridFeatures)
        let side = ImagePreprocessor.gridSide

        for cy in 0..<cells {
            for cx in 0..<cells {
                var sum = 0.0
                for y in 0..<pool {
                    for x in 0..<pool {
                        sum += grid[(cy * pool + y) * side + cx * pool + x]
                    }
                }
                pooled[cy * cells + cx] = sum / Double(pool * pool)
            }
        }

        return pooled
    }

    /// Count of 4-connected mask transitions — a discrete perimeter estimate.
    static func perimeter(_ mask: [UInt8], width: Int, height: Int) -> Int {
        var edges = 0

        for y in 0..<height {
            for x in 0..<width {
                let value = mask[y * width + x]
                if x + 1 < width, value != mask[y * width + x + 1] { edges += 1 }
                if y + 1 < height, value != mask[(y + 1) * width + x] { edges += 1 }
            }
        }

        return edges
    }

    /// Ramer-Douglas-Peucker on the convex hull. The number of vertices that survive is the
    /// classic separator for convex shapes: 3 for a triangle, 4 for a square, many for a circle.
    /// Tolerance scales with the hull's size, so the count does not depend on resolution.
    static func cornerCount(_ hull: [SIMD2<Double>]) -> Int {
        guard hull.count >= 3 else { return 0 }

        var perimeter = 0.0
        for index in hull.indices {
            perimeter += (hull[(index + 1) % hull.count] - hull[index]).length
        }
        let tolerance = max(1, 0.025 * perimeter)

        func distance(_ point: SIMD2<Double>, _ from: SIMD2<Double>, _ to: SIMD2<Double>) -> Double {
            let delta = to - from
            let length = delta.length
            if length == 0 { return (point - from).length }
            return abs(delta.y * point.x - delta.x * point.y + to.x * from.y - to.y * from.x) / length
        }

        func simplify(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
            guard points.count >= 3 else { return points }
            var worst = 0.0
            var index = 0
            for i in 1..<(points.count - 1) {
                let d = distance(points[i], points[0], points[points.count - 1])
                if d > worst {
                    worst = d
                    index = i
                }
            }
            if worst <= tolerance { return [points[0], points[points.count - 1]] }
            return simplify(Array(points[0...index])).dropLast() + simplify(Array(points[index...]))
        }

        // Split the closed hull at its two most distant vertices so RDP sees two open chains.
        var a = 0
        var b = 0
        var best = -1.0
        for i in hull.indices {
            for j in (i + 1)..<hull.count {
                let d = (hull[i] - hull[j]).length
                if d > best {
                    best = d
                    a = i
                    b = j
                }
            }
        }

        let first = Array(hull[a...b])
        let second = Array(hull[b...]) + Array(hull[0...a])
        return simplify(first).count + simplify(second).count - 2
    }

    /// Rotating calipers: area of the hull over the area of its smallest enclosing rectangle.
    /// Unlike area / bounding box this does not change when the figure is rotated —
    /// ~1.0 for a square, ~0.785 for a circle, ~0.5 for a triangle at any angle.
    static func rectangularity(_ hull: [SIMD2<Double>]) -> Double {
        guard hull.count >= 3 else { return 0 }

        var area = 0.0
        for index in hull.indices {
            let a = hull[index]
            let b = hull[(index + 1) % hull.count]
            area += a.x * b.y - b.x * a.y
        }
        area = abs(area) / 2
        guard area > 0 else { return 0 }

        var smallest = Double.infinity
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

            smallest = min(smallest, (maxU - minU) * (maxV - minV))
        }

        guard smallest.isFinite, smallest > 0 else { return 0 }
        return min(area / smallest, 1)
    }

    static func geometry(_ mask: [UInt8], width: Int, height: Int, hull: [SIMD2<Double>]) -> ShapeGeometry {
        var area = 0
        for value in mask {
            area += Int(value)
        }

        let fill = Double(area) / Double(width * height)

        let edges = perimeter(mask, width: width, height: height)
        let compactness = min(4 * Double.pi * Double(area) / Double(max(edges * edges, 1)), 1)

        let half = height / 2
        var top = 0
        var bottom = 0
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] != 0 {
                if y < half { top += 1 } else { bottom += 1 }
            }
        }
        let topMean = half > 0 ? Double(top) / Double(half * width) : 0
        let bottomMean = (height - half) > 0 ? Double(bottom) / Double((height - half) * width) : 0
        let symmetry = min(topMean / max(bottomMean, 1e-3), 2) / 2

        return ShapeGeometry(
            fill: fill,
            compactness: compactness,
            symmetry: symmetry,
            corners: cornerCount(hull),
            rectangularity: rectangularity(hull)
        )
    }

    static func extract(from image: GrayscaleImage) -> FigureFeatures? {
        guard let normalised = ImagePreprocessor.normalise(image) else { return nil }
        return extract(from: normalised)
    }

    static func extract(from normalised: NormalisedShape) -> FigureFeatures {
        let cellValues = poolGrid(normalised.grid)
        let shape = geometry(normalised.mask, width: normalised.width, height: normalised.height, hull: normalised.hull)

        var values = cellValues
        values.append(shape.fill)
        values.append(shape.compactness)
        values.append(shape.symmetry)
        values.append(Double(min(shape.corners, maxCorners)) / Double(maxCorners))
        values.append(shape.rectangularity)

        return FigureFeatures(values: values, cells: cellValues, geometry: shape)
    }
}
