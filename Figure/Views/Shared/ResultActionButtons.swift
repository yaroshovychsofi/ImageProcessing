import SwiftUI

struct ResultActionButtons: View {
    let primarySave: Bool
    var controlHeight = 58.0
    let onSave: () -> Void
    let shareText: String

    var body: some View {
        HStack(spacing: 12) {
            actionButton(
                title: "Зберегти",
                systemImage: "arrow.down.to.line",
                isPrimary: primarySave,
                action: onSave
            )

            ShareLink(item: shareText) {
                actionLabel(
                    title: "Поділитися",
                    systemImage: "square.and.arrow.up",
                    isPrimary: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(
                title: title,
                systemImage: systemImage,
                isPrimary: isPrimary
            )
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(
        title: String,
        systemImage: String,
        isPrimary: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: controlHeight)
            .foregroundStyle(isPrimary ? Color.white : AppTheme.accent)
            .background(isPrimary ? AppTheme.accent : AppTheme.accentTint)
            .clipShape(.rect(cornerRadius: 18))
    }
}
