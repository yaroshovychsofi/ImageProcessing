import SwiftUI

struct RecognitionDistributionView: View {
    let scores: [RecognitionScore]
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 7 : 12) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                RecognitionScoreRow(
                    score: score,
                    isPrimary: index == 0,
                    isCompact: isCompact
                )
            }
        }
    }
}
