import SwiftUI

struct FileMetadataView: View {
    let selection: SelectedImage?
    let onShowInfo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection?.fileName ?? "Файл не вибрано")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Інформація про файл", systemImage: "info.circle", action: onShowInfo)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 44)
                .disabled(selection == nil)
        }
        .frame(minHeight: 52)
    }

    private var metadata: String {
        guard let selection else { return "PNG, JPG, JPEG або BMP" }
        return "\(selection.format) · \(selection.resolution) · \(selection.size)"
    }
}

