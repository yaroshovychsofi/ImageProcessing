import SwiftUI

struct CustomImageOptionCard: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(red: 0.137, green: 0.529, blue: 0.396))
                    .frame(width: 38, height: 38)

                Text("Вибрати\nсвоє")
                    .font(.caption)
                    .bold()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                isSelected
                    ? Color(red: 0.847, green: 0.949, blue: 0.910)
                    : Color(red: 0.918, green: 0.973, blue: 0.953)
            )
            .clipShape(.rect(cornerRadius: AppTheme.smallRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                    .stroke(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Вибрати власне зображення")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

