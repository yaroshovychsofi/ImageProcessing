import SwiftUI

struct HistoryScreen: View {
    @Bindable var store: RecognitionStore
    @State private var isConfirmingClear = false

    var body: some View {
        Group {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "Історія порожня",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Виконайте розпізнавання, і результат з’явиться тут.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.history) { record in
                            NavigationLink(value: RecognitionRoute.detail(record)) {
                                HistoryRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppTheme.screenPadding)
                }
                .scrollContentBackground(.visible)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Історія")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Очистити історію", systemImage: "trash", action: confirmClearHistory)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .confirmationDialog(
            "Очистити всю історію?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Очистити", role: .destructive, action: store.clearHistory)
            Button("Скасувати", role: .cancel) { }
        } message: {
            Text("Цю дію неможливо скасувати.")
        }
    }

    private func confirmClearHistory() {
        isConfirmingClear = true
    }
}

