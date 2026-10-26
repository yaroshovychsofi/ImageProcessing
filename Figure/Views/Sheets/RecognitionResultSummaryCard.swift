import SwiftUI

struct RecognitionResultSummaryCard: View {
    let record: RecognitionRecord

    var body: some View {
        HStack(spacing: 12) {
            SelectedImageView(image: record.image, contentMode: .fit, symbolScale: 0.58)
                .frame(width: 72, height: 72)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 16))
                .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Label("Розпізнавання завершено", systemImage: "checkmark")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 0.06, green: 0.58, blue: 0.34))
                    .labelStyle(.titleAndIcon)

                Text(record.predictedClass.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(AppTheme.textPrimary)

                Text(record.modelTitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(ConfidenceText.percent(record.confidence))
                    .font(.title2)
                    .bold()
                    .foregroundStyle(AppTheme.accent)

                Text("Упевненість\nмоделі")
                    .font(.caption2)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
