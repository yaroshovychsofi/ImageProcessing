import SwiftUI

struct EmptyImagePreviewView: View {
    let onSelectImage: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 25))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 56, height: 56)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityHidden(true)

            Text("Зображення не вибрано")
                .font(.headline)
                .bold()
                .foregroundStyle(AppTheme.textPrimary)

            Text("Оберіть приклад або додайте власне зображення.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)

            Button("Додати зображення", action: onSelectImage)
                .font(.headline)
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(minHeight: 48)
                .background(AppTheme.accent)
                .clipShape(.capsule)
                .padding(.top, 4)
        }
        .padding(20)
        .accessibilityElement(children: .contain)
    }
}

