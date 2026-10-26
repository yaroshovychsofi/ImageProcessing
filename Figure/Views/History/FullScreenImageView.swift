import SwiftUI

struct FullScreenImageView: View {
    @Environment(\.dismiss) private var dismiss

    let image: SelectedImage

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if image.sample == nil {
                SelectedImageView(image: image, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                SelectedImageView(
                    image: image,
                    contentMode: .fit,
                    symbolScale: 0.48
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(AppTheme.secondarySurface)
                .clipShape(.rect(cornerRadius: 28))
                .padding(20)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()

                Button("Закрити повноекранний перегляд", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(.circle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .background(Color.black)
        .statusBarHidden()
    }
}
