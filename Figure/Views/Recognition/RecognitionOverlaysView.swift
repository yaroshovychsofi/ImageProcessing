import SwiftUI

struct RecognitionOverlaysView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: RecognitionStore
    @Binding var isShowingImageSource: Bool
    @Binding var isShowingAbout: Bool
    @Binding var infoImage: SelectedImage?

    var body: some View {
        ZStack {
            if isShowingImageSource {
                BottomSheetContainer(onDismiss: dismissImageSource) {
                    ImageSourceSheet(
                        onDismiss: dismissImageSource,
                        onImageSelected: selectCustomImage
                    )
                }
            }

            if let infoImage {
                BottomSheetContainer(onDismiss: dismissImageInfo) {
                    ImageInfoSheet(
                        image: infoImage,
                        onDismiss: dismissImageInfo
                    )
                }
            }

            if isShowingAbout {
                BottomSheetContainer(onDismiss: dismissAbout) {
                    AboutSheet(onDismiss: dismissAbout)
                }
            }

            if let result = store.presentedResult {
                BottomSheetContainer(onDismiss: dismissResult) {
                    RecognitionResultSheet(
                        record: result,
                        onClose: dismissResult,
                        onRecognizeAnother: recognizeAnother
                    )
                }
            }
        }
        .animation(sheetAnimation, value: isShowingImageSource)
        .animation(sheetAnimation, value: isShowingAbout)
        .animation(sheetAnimation, value: infoImage?.id)
        .animation(sheetAnimation, value: store.presentedResult?.id)
    }

    private var sheetAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.28)
    }

    private func dismissImageSource() {
        isShowingImageSource = false
    }

    private func selectCustomImage(_ image: SelectedImage) {
        store.selectCustomImage(image)
        isShowingImageSource = false
    }

    private func dismissImageInfo() {
        infoImage = nil
    }

    private func dismissAbout() {
        isShowingAbout = false
    }

    private func dismissResult() {
        store.presentedResult = nil
    }

    private func recognizeAnother() {
        store.presentedResult = nil
        store.selectedImage = nil
        store.progress = 0
    }
}
