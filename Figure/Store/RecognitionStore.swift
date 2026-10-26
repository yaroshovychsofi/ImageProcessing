import Observation
import SwiftUI

@MainActor
@Observable
final class RecognitionStore {
    var selectedImage: SelectedImage?
    var inputMode = InputMode.original
    var history: [RecognitionRecord] = []
    var progress = 0.0
    var isRecognizing = false
    var presentedResult: RecognitionRecord?
    var errorMessage: String?
    /// 8x8 cell intensities of the current selection, shown by the "Вхід мережі" mode.
    var networkPreview: [Double]?

    init() {
        history = RecognitionHistoryCache.load()
    }

    func selectSample(_ figure: FigureClass) {
        selectedImage = .sample(figure)
        inputMode = .original
        networkPreview = nil
    }

    func selectCustomImage(_ image: SelectedImage) {
        selectedImage = image
        inputMode = .original
        networkPreview = nil
    }

    func recognize() async {
        guard let selectedImage, !isRecognizing else { return }

        isRecognizing = true
        progress = 0
        errorMessage = nil

        do {
            guard let image = rasterize(selectedImage) else {
                throw RecognitionError.unreadableImage
            }

            let outcome = try await FigureRecognizer.shared.recognise(image) { [weak self] value in
                await MainActor.run { self?.progress = value }
            }

            let record = makeRecord(for: selectedImage, outcome: outcome)
            OperationLog.shared.add(String(format: "Розпізнавання: %@ (%.1f %%) за %@, %@.",
                                           FigureClass.allCases[outcome.bestIndex].title, outcome.confidence * 100,
                                           outcome.duration.formattedSeconds,
                                           outcome.usedTrainedModel ? "модель з застосунку" : "вбудована модель"), level: .success)
            history.insert(record, at: 0)
            history = Array(history.prefix(50))
            persistHistory()
            networkPreview = outcome.cells
            presentedResult = record
        } catch is CancellationError {
            progress = 0
        } catch {
            progress = 0
            errorMessage = error.localizedDescription
            OperationLog.shared.add("Розпізнавання не вдалося: \(error.localizedDescription)", level: .error)
        }

        isRecognizing = false
    }

    /// The preview is computed on demand: the user only pays for it after switching the mode.
    func refreshNetworkPreview() async {
        guard inputMode == .networkInput, let selectedImage else { return }
        guard networkPreview == nil else { return }
        guard let image = rasterize(selectedImage) else { return }

        networkPreview = await Task.detached {
            try? await FigureRecognizer.shared.previewCells(for: image)
        }.value
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func delete(_ record: RecognitionRecord) {
        history.removeAll { $0.id == record.id }
        persistHistory()
    }

    private func makeRecord(for image: SelectedImage, outcome: RecognitionOutcome) -> RecognitionRecord {
        let classes = FigureClass.allCases
        let scores = zip(classes, outcome.normalised)
            .map { RecognitionScore(figure: $0, confidence: $1) }
            .sorted { $0.confidence > $1.confidence }

        return RecognitionRecord(
            image: image,
            predictedClass: classes[outcome.bestIndex],
            confidence: outcome.confidence,
            scores: scores,
            networkInput: outcome.cells,
            durationMilliseconds: outcome.duration.milliseconds,
            usedTrainedModel: outcome.usedTrainedModel
        )
    }

    private func rasterize(_ image: SelectedImage) -> CGImage? {
        if let data = image.imageData {
            return UIImage(data: data)?.cgImage
        }
        if let sample = image.sample {
            return SampleRasterizer.render(sample)
        }
        return nil
    }

    private func persistHistory() {
        RecognitionHistoryCache.save(history)
    }
}

private extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
