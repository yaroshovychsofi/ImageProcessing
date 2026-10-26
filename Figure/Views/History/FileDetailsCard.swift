import SwiftUI

struct FileDetailsCard: View {
    let image: SelectedImage

    var body: some View {
        VStack(spacing: 0) {
            MetadataRow(
                title: "Джерело",
                value: image.sample == nil ? "Власне зображення" : "Готовий приклад"
            )
                .padding(.vertical, 8)
            Divider()
            MetadataRow(title: "Формат", value: image.format)
                .padding(.vertical, 8)
            Divider()
            MetadataRow(title: "Роздільна здатність", value: image.resolution)
                .padding(.vertical, 8)
            Divider()
            MetadataRow(title: "Розмір файла", value: image.size)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 18)
        .background(AppTheme.surface)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
