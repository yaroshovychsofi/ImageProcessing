import SwiftUI

struct AboutSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BottomSheetHeader(
                title: "Про застосунок",
                onClose: onDismiss
            )

            Label("Розпізнавання трьох образів", systemImage: "viewfinder")
                .font(.headline)

            Text("Оберіть коло, квадрат або трикутник із готових прикладів чи додайте власне зображення. Після розпізнавання результат буде збережено в історії.")
                .foregroundStyle(AppTheme.textSecondary)

        }
        .padding(20)
        .background(AppTheme.background)
    }
}
