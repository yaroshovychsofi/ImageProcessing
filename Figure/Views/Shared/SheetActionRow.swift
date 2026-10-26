import SwiftUI

struct SheetActionRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accentTint)
                .clipShape(.rect(cornerRadius: 14))

            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundStyle(AppTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 62)
        .background(AppTheme.surface)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
