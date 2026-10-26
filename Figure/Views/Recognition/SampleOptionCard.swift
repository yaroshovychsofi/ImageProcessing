import SwiftUI

struct SampleOptionCard: View {
    let figure: FigureClass
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                FigureSymbolView(figure: figure, color: figure.iconColor)
                    .frame(width: 38, height: 38)

                Text(figure.title)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(isSelected ? figure.selectedTint : figure.tint)
            .clipShape(.rect(cornerRadius: AppTheme.smallRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                    .stroke(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Вибрати приклад: \(figure.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

