import SwiftUI

struct BottomSheetCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button("Скасувати", action: action)
            .font(.headline)
            .bold()
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AppTheme.accentTint)
            .clipShape(.rect(cornerRadius: 16))
    }
}

