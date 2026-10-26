import SwiftUI

struct RecognitionDistributionCard: View {
    let record: RecognitionRecord

    var body: some View {
        RecognitionDistributionView(scores: record.scores, isCompact: true)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AppTheme.surface)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
