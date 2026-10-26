import CoreGraphics
import Foundation
import ImageIO
import OSLog

/// Preprocessing and feature extraction exist twice: in JavaScript (to build the training set)
/// and in Swift (to evaluate images in the app). If the two ever diverge, the network silently
/// receives inputs it was not trained on. The trainer therefore exports reference vectors
/// computed by Brain.js, and this check recomputes them from the bundled images.
nonisolated enum FixtureValidator {
    struct Report: Sendable {
        var checked = 0
        var featureMismatches = 0
        var outputMismatches = 0
        var labelMismatches = 0
        var maxFeatureDeviation = 0.0
        var maxOutputDeviation = 0.0
        /// Which fixture and which feature drifted the most — without it a mismatch report
        /// says that something diverged but not where to look.
        var worstFixture = ""
        var worstFeatureIndex = -1

        var isValid: Bool { featureMismatches == 0 && outputMismatches == 0 && labelMismatches == 0 }
    }

    nonisolated private struct Fixtures: Decodable {
        nonisolated struct Fixture: Decodable {
            let bundleName: String
            let label: String
            let labelIndex: Int
            let features: [Double]
            let output: [Double]
        }

        let featureCount: Int
        let classes: [String]
        let fixtures: [Fixture]
    }

    static let featureTolerance = 1e-9
    static let outputTolerance = 1e-6

    static func run() async -> Report? {
        guard let url = Bundle.main.url(forResource: "fixtures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixtures = try? JSONDecoder().decode(Fixtures.self, from: data)
        else { return nil }

        guard let network = try? await FigureRecognizer.shared.network() else { return nil }

        var report = Report()

        for fixture in fixtures.fixtures {
            guard let image = loadImage(named: fixture.bundleName),
                  let grayscale = ImagePreprocessor.grayscale(from: image),
                  let features = FeatureExtractor.extract(from: grayscale),
                  features.values.count == fixture.features.count
            else { continue }

            report.checked += 1

            var featureDeviation = 0.0
            var featureIndex = -1
            for (index, pair) in zip(features.values, fixture.features).enumerated() where abs(pair.0 - pair.1) > featureDeviation {
                featureDeviation = abs(pair.0 - pair.1)
                featureIndex = index
            }
            if featureDeviation > report.maxFeatureDeviation {
                report.maxFeatureDeviation = featureDeviation
                report.worstFixture = fixture.bundleName
                report.worstFeatureIndex = featureIndex
            }
            if featureDeviation > featureTolerance { report.featureMismatches += 1 }

            let outputs = network.run(features.values)
            var outputDeviation = 0.0
            for (computed, expected) in zip(outputs, fixture.output) {
                outputDeviation = max(outputDeviation, abs(computed - expected))
            }
            report.maxOutputDeviation = max(report.maxOutputDeviation, outputDeviation)
            if outputDeviation > outputTolerance { report.outputMismatches += 1 }

            var bestIndex = 0
            for index in 1..<outputs.count where outputs[index] > outputs[bestIndex] {
                bestIndex = index
            }
            if bestIndex != fixture.labelIndex { report.labelMismatches += 1 }
        }

        log(report)
        return report
    }

    private static func loadImage(named name: String) -> CGImage? {
        let components = name.split(separator: ".")
        guard components.count == 2,
              let url = Bundle.main.url(forResource: String(components[0]), withExtension: String(components[1])),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func log(_ report: Report) {
        let logger = Logger(subsystem: "com.sofiia.FigureRecognition", category: "fixtures")
        if report.isValid {
            logger.info("""
            fixtures ok: \(report.checked) vectors, \
            max feature deviation \(report.maxFeatureDeviation), \
            max output deviation \(report.maxOutputDeviation)
            """)
        } else {
            logger.error("""
            fixtures mismatch: \(report.featureMismatches) feature, \
            \(report.outputMismatches) output, \(report.labelMismatches) label — \
            Swift preprocessing diverged from the JavaScript trainer. \
            worst: \(report.worstFixture) feature #\(report.worstFeatureIndex) \
            by \(report.maxFeatureDeviation)
            """)
        }
    }
}
