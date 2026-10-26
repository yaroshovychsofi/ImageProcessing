import SwiftUI

struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
