import SwiftUI

struct RecognitionDetailActions: View {
    let onSave: () -> Void
    let shareText: String

    var body: some View {
        ResultActionButtons(
            primarySave: false,
            controlHeight: 48,
            onSave: onSave,
            shareText: shareText
        )
    }
}
