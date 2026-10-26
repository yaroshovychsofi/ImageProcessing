import SwiftUI

struct RecognitionDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingExportFormat = false
    @State private var isShowingFullScreenImage = false
    @State private var isConfirmingDelete = false

    let record: RecognitionRecord
    let store: RecognitionStore

    var body: some View {
        GeometryReader { proxy in
            let imageHeight = min(190, max(150, proxy.size.height * 0.24))

            VStack(alignment: .leading, spacing: 10) {
                RecognitionDetailsCard(
                    record: record,
                    imageHeight: imageHeight,
                    onImageTapped: showFullScreenImage
                )

                DetailSectionTitle(title: "Розподіл результатів")

                RecognitionDistributionCard(record: record)

                if record.networkInput.count == 64 {
                    DetailSectionTitle(title: "Вхід мережі")

                    NetworkInputGridView(cells: record.networkInput, size: 200)
                        .padding(12)
                        .background(AppTheme.surface)
                        .clipShape(.rect(cornerRadius: AppTheme.cardRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                }

                DetailSectionTitle(title: "Інформація про файл")

                FileDetailsCard(image: record.image)

                RecognitionDetailActions(
                    onSave: saveResult,
                    shareText: record.shareText
                )
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("Деталі")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive, action: confirmDelete) {
                    Label("Видалити з історії", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .tint(.red)
                .confirmationDialog(
                    "Видалити цей запис?",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Видалити", role: .destructive, action: deleteRecord)
                    Button("Скасувати", role: .cancel) { }
                } message: {
                    Text("Запис буде видалено з історії та локального кешу.")
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingFullScreenImage) {
            FullScreenImageView(image: record.image)
        }
        .recognitionExport(record: record, isChoosingFormat: $isChoosingExportFormat)
    }

    private func saveResult() {
        isChoosingExportFormat = true
    }

    private func showFullScreenImage() {
        isShowingFullScreenImage = true
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func deleteRecord() {
        store.delete(record)
        dismiss()
    }
}
