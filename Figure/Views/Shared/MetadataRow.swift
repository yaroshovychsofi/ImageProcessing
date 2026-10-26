import SwiftUI

struct MetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
