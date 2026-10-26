import SwiftUI

struct HistoryRow: View {
    let record: RecognitionRecord

    var body: some View {
        HStack(spacing: 16) {
            SelectedImageView(image: record.image, contentMode: .fill, symbolScale: 0.58)
                .frame(width: 72, height: 72)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 16))
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(record.predictedClass.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 5) {
                    Text(ConfidenceText.percent(record.confidence))
                    Text("·")
                    RecognitionDateLabel(date: record.createdAt)
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundStyle(AppTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(minHeight: 104)
        .background(AppTheme.surface)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
