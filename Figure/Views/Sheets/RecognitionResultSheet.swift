import SwiftUI

struct RecognitionResultSheet: View {
    @State private var isChoosingExportFormat = false

    let record: RecognitionRecord
    let onClose: () -> Void
    let onRecognizeAnother: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            BottomSheetHeader(
                title: "Результат",
                onClose: onClose
            )

            RecognitionResultSummaryCard(record: record)

            RecognitionDistributionView(scores: record.scores)

            ResultActionButtons(
                primarySave: true,
                onSave: saveResult,
                shareText: record.shareText
            )

            Button("Розпізнати інше", action: onRecognizeAnother)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 18))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(AppTheme.background)
        .recognitionExport(record: record, isChoosingFormat: $isChoosingExportFormat)
    }

    private func saveResult() {
        isChoosingExportFormat = true
    }
}
