import SwiftUI

struct RecognitionExportCard: View {
    let record: RecognitionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Результат розпізнавання")
                .font(.title2)
                .bold()
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 16) {
                SelectedImageView(
                    image: record.image,
                    contentMode: .fit,
                    symbolScale: 0.58
                )
                .frame(width: 88, height: 88)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text(record.predictedClass.title)
                        .font(.title2)
                        .bold()

                    Text(ConfidenceText.percent(record.confidence))
                        .font(.title3)
                        .bold()
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Розподіл результатів")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textSecondary)

                RecognitionDistributionView(scores: record.scores)
            }

            Text(record.createdAt, format: .dateTime.day().month().year().hour().minute())
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(24)
        .frame(width: 360)
        .background(AppTheme.surface)
    }
}
