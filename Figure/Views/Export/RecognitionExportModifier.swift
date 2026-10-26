import SwiftUI

/// Saving a result is identical on the result sheet and in the history details, so the format
/// picker, the file exporter and the alerts live here instead of being duplicated in both.
private struct RecognitionExportModifier: ViewModifier {
    let record: RecognitionRecord
    @Binding var isChoosingFormat: Bool

    @State private var document: RecognitionResultDocument?
    @State private var format = ExportFormat.png
    @State private var isExporting = false
    @State private var isShowingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Зберегти результат",
                isPresented: $isChoosingFormat,
                titleVisibility: .visible
            ) {
                ForEach(ExportFormat.allCases) { option in
                    Button("\(option.title) — \(option.subtitle)") {
                        prepare(option)
                    }
                }
                Button("Скасувати", role: .cancel) { }
            } message: {
                Text("Оберіть формат файлу зображення.")
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: format.contentType,
                defaultFilename: RecognitionResultExporter.defaultFileName(for: record),
                onCompletion: handleExport
            )
            .alert(alertTitle, isPresented: $isShowingAlert) {
            } message: {
                Text(alertMessage)
            }
    }

    private func prepare(_ option: ExportFormat) {
        guard let data = RecognitionResultExporter.makeData(for: record, format: option) else {
            showAlert(
                title: "Не вдалося зберегти",
                message: "Не вдалося сформувати зображення результату у форматі \(option.title)."
            )
            return
        }

        format = option
        document = RecognitionResultDocument(data: data)
        isExporting = true
    }

    private func handleExport(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            showAlert(
                title: "Результат збережено",
                message: "Файл \(format.title) успішно збережено у вибраному місці."
            )
        case .failure(let error):
            showAlert(title: "Не вдалося зберегти", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isShowingAlert = true
    }
}

extension View {
    func recognitionExport(record: RecognitionRecord, isChoosingFormat: Binding<Bool>) -> some View {
        modifier(RecognitionExportModifier(record: record, isChoosingFormat: isChoosingFormat))
    }
}
