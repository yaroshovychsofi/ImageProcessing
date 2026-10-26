import SwiftUI

struct RecognitionDetailsCard: View {
    let record: RecognitionRecord
    let imageHeight: Double
    let onImageTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onImageTapped) {
                ZStack(alignment: .topTrailing) {
                    SelectedImageView(image: record.image, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: imageHeight)
                        .background(AppTheme.secondarySurface)
                        .clipShape(.rect(cornerRadius: 20))
                        .clipped()

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(.circle)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Відкрити зображення на весь екран")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.predictedClass.title)
                        .font(.title3)
                        .bold()
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Text(ConfidenceText.percent(record.confidence))
                        .font(.title3)
                        .bold()
                        .foregroundStyle(AppTheme.accent)
                }

                HStack(spacing: 6) {
                    RecognitionDateLabel(date: record.createdAt)

                    if record.durationMilliseconds > 0 {
                        Text("· алгоритм \(record.durationMilliseconds, format: .number.precision(.fractionLength(record.durationMilliseconds < 10 ? 1 : 0))) мс")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(.rect(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
