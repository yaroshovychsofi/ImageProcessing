import SwiftUI

struct BottomSheetContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: onDismiss) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.16))
                    .contentShape(.rect)
            }
                .accessibilityLabel("Закрити нижню панель")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .buttonStyle(.plain)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(red: 0.584, green: 0.604, blue: 0.671))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)

                content
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.background)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    topTrailingRadius: 32
                )
            )
            .shadow(color: .black.opacity(0.12), radius: 24, y: -6)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity)
            )
        }
        .ignoresSafeArea()
    }
}
