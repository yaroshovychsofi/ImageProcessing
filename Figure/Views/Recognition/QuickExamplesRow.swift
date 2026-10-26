import SwiftUI

struct QuickExamplesRow: View {
    let selection: SelectedImage?
    let onSelectSample: (FigureClass) -> Void
    let onSelectCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Спробувати приклад")
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach(FigureClass.allCases) { figure in
                    SampleOptionCard(
                        figure: figure,
                        isSelected: selection?.sample == figure,
                        action: { onSelectSample(figure) }
                    )
                }

                CustomImageOptionCard(
                    isSelected: selection?.imageData != nil,
                    action: onSelectCustom
                )
            }
        }
    }
}

