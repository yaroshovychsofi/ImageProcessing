import SwiftUI

struct ImagePreviewCard: View {
    let selection: SelectedImage?
    let inputMode: InputMode
    let networkPreview: [Double]?
    let onChange: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .fill(AppTheme.surface)
                .stroke(AppTheme.border, lineWidth: 1)

            if let selection {
                if inputMode == .networkInput {
                    NetworkInputGridView(cells: networkPreview)
                        .padding(30)
                } else {
                    SelectedImageView(image: selection)
                        .padding(30)
                }

                VStack {
                    HStack {
                        Spacer()
                        Button("Змінити", systemImage: "arrow.triangle.2.circlepath", action: onChange)
                            .font(.subheadline)
                            .bold()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(AppTheme.accent)
                            .background(.ultraThinMaterial)
                            .clipShape(.capsule)
                    }
                    Spacer()
                }
                .padding(12)
            } else {
                EmptyImagePreviewView(onSelectImage: onChange)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
