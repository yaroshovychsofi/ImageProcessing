import SwiftUI

struct RecognizeButton: View {
    let isEnabled: Bool
    let isRecognizing: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Label(isRecognizing ? "Розпізнавання…" : "Розпізнати", systemImage: "viewfinder")
                    .font(.headline)
                    .bold()

                if isRecognizing {
                    ProgressView(value: progress)
                        .tint(.white)
                        .accessibilityLabel("Прогрес розпізнавання")
                        .accessibilityValue(Text(progress, format: .percent))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 20)
            .background(isEnabled ? AppTheme.accent : AppTheme.disabled)
            .clipShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .white : AppTheme.disabledText)
        .disabled(!isEnabled || isRecognizing)
        .sensoryFeedback(.success, trigger: progress == 1)
    }
}
