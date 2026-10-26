import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImageSourceSheet: View {
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingFileImporter = false
    @State private var isShowingError = false
    @State private var errorMessage: String?

    let onDismiss: () -> Void
    let onImageSelected: (SelectedImage) -> Void

    var body: some View {
        VStack(spacing: 12) {
            BottomSheetHeader(
                title: "Змінити зображення",
                onClose: onDismiss
            )

            PhotosPicker(selection: $photoItem, matching: .images) {
                SheetActionRow(title: "Обрати з Фото", systemImage: "photo")
            }
            .buttonStyle(.plain)

            Button(action: showFileImporter) {
                SheetActionRow(title: "Обрати з Файлів", systemImage: "folder")
            }
            .buttonStyle(.plain)

            BottomSheetCancelButton(action: onDismiss)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .background(AppTheme.background)
        .onChange(of: photoItem, loadSelectedPhoto)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .alert("Не вдалося відкрити зображення", isPresented: $isShowingError) {
        } message: {
            Text(errorMessage ?? "Невідома помилка")
        }
    }

    private func showFileImporter() {
        isShowingFileImporter = true
    }

    private func loadSelectedPhoto() {
        guard let photoItem else { return }

        Task {
            do {
                guard let data = try await photoItem.loadTransferable(type: Data.self),
                      let selectedImage = ImageImportFactory.makeImage(data: data) else {
                    showError("Файл не є підтримуваним зображенням.")
                    return
                }

                onImageSelected(selectedImage)
                onDismiss()
            } catch {
                showError("Не вдалося завантажити вибране фото.")
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let format = ImageImportFactory.detectFormat(from: data)?.name
                ?? (url.pathExtension.isEmpty ? "IMAGE" : url.pathExtension)

            guard let selectedImage = ImageImportFactory.makeImage(
                data: data,
                fileName: url.lastPathComponent,
                format: format
            ) else {
                showError("Файл не є підтримуваним зображенням.")
                return
            }

            onImageSelected(selectedImage)
            onDismiss()
        } catch {
            showError("Не вдалося прочитати вибраний файл.")
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
