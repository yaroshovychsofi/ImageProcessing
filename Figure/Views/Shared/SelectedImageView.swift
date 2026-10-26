import SwiftUI

struct SelectedImageView: View {
    let image: SelectedImage
    var contentMode: ContentMode = .fit
    var symbolScale = 0.36

    var body: some View {
        Group {
            if let imageData = image.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let sample = image.sample {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height) * symbolScale
                    FigureSymbolView(figure: sample)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .padding(34)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .accessibilityLabel(image.sample?.title ?? "Вибране зображення")
    }
}
