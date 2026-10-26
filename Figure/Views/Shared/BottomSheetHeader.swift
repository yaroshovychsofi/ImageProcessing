import SwiftUI

struct BottomSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title2)
                .bold()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Button("Закрити", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(AppTheme.secondarySurface)
                .clipShape(.circle)
        }
    }
}

