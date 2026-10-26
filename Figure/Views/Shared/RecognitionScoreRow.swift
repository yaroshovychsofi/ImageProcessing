import SwiftUI

struct RecognitionScoreRow: View {
    let score: RecognitionScore
    let isPrimary: Bool
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 3 : 5) {
            HStack {
                Text(score.figure.title)
                    .font(.subheadline)
                    .fontWeight(isPrimary ? .semibold : .regular)
                    .foregroundStyle(isPrimary ? AppTheme.textPrimary : AppTheme.textSecondary)

                Spacer()

                Text(ConfidenceText.percent(score.confidence))
                    .font(.subheadline)
                    .fontWeight(isPrimary ? .bold : .semibold)
                    .foregroundStyle(isPrimary ? AppTheme.textPrimary : AppTheme.textSecondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.disabled)

                    Capsule()
                        .fill(isPrimary ? AppTheme.accent : AppTheme.textTertiary)
                        .frame(width: max(5, proxy.size.width * score.confidence))
                }
            }
            .frame(height: isCompact ? 4 : 5)
        }
        .accessibilityElement(children: .combine)
    }
}
