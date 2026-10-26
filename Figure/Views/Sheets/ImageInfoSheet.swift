import SwiftUI

struct ImageInfoSheet: View {
    let image: SelectedImage
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BottomSheetHeader(
                title: "Інформація про файл",
                onClose: onDismiss
            )

            SelectedImageView(image: image, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 18))
                .clipped()

            VStack(spacing: 0) {
                MetadataRow(title: "Назва", value: image.fileName)
                    .padding(.vertical, 8)
                Divider()
                MetadataRow(title: "Формат", value: image.format)
                    .padding(.vertical, 8)
                Divider()
                MetadataRow(title: "Роздільна здатність", value: image.resolution)
                    .padding(.vertical, 8)
                Divider()
                MetadataRow(title: "Розмір", value: image.size)
                    .padding(.vertical, 8)
                Divider()
                MetadataRow(title: "Колірний простір", value: image.colorSpace)
                    .padding(.vertical, 8)
                Divider()
                MetadataRow(title: "Вибрано", value: selectedAtText)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 18)
            .background(AppTheme.surface)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(AppTheme.background)
    }

    private var selectedAtText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm:ss"
        return formatter.string(from: image.selectedAt)
    }
}
