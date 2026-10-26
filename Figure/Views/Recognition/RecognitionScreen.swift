import SwiftUI

struct RecognitionScreen: View {
    @Bindable var store: RecognitionStore
    @State private var path: [RecognitionRoute] = []
    @State private var isShowingImageSource = false
    @State private var isShowingAbout = false
    @State private var infoImage: SelectedImage?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                QuickExamplesRow(
                    selection: store.selectedImage,
                    onSelectSample: store.selectSample,
                    onSelectCustom: showImageSource
                )

                ImagePreviewCard(
                    selection: store.selectedImage,
                    inputMode: store.inputMode,
                    networkPreview: store.networkPreview,
                    onChange: showImageSource
                )

                FileMetadataView(
                    selection: store.selectedImage,
                    onShowInfo: showImageInfo
                )

                InputModePicker(
                    selection: $store.inputMode,
                    isEnabled: store.selectedImage != nil
                )

                RecognizeButton(
                    isEnabled: store.selectedImage != nil,
                    isRecognizing: store.isRecognizing,
                    progress: store.progress,
                    action: recognize
                )
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.bottom, 12)
            .background(AppTheme.background)
            .task(id: previewToken) {
                await store.refreshNetworkPreview()
            }
            .alert(
                "Не вдалося розпізнати",
                isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
            ) {
                Button("Зрозуміло") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Розпізнавання")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(AppTheme.textPrimary)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Історія розпізнавань", systemImage: "clock.arrow.circlepath", action: showHistory)
                    Button("Про застосунок", systemImage: "info.circle", action: showAbout)
                }
            }
            .navigationDestination(for: RecognitionRoute.self) { route in
                RecognitionDestinationView(route: route, store: store)
            }
        }
        .overlay {
            RecognitionOverlaysView(
                store: store,
                isShowingImageSource: $isShowingImageSource,
                isShowingAbout: $isShowingAbout,
                infoImage: $infoImage
            )
        }
    }

    private var previewToken: String {
        "\(store.selectedImage?.id.uuidString ?? "none")-\(store.inputMode.rawValue)"
    }

    private func showHistory() {
        path.append(.history)
    }

    private func showAbout() {
        isShowingAbout = true
    }

    private func showImageSource() {
        isShowingImageSource = true
    }

    private func showImageInfo() {
        infoImage = store.selectedImage
    }

    private func recognize() {
        Task {
            await store.recognize()
        }
    }
}

#Preview {
    RecognitionScreen(store: RecognitionStore())
}
