import SwiftUI

struct LogScreen: View {
    let log = OperationLog.shared

    var body: some View {
        NavigationStack {
            List(log.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message).font(.callout)
                    Text("\(entry.date.formatted(date: .omitted, time: .standard)) · \(entry.level.rawValue)")
                        .font(.caption2).foregroundStyle(color(entry.level))
                }
            }
            .overlay {
                if log.entries.isEmpty { ContentUnavailableView("Лог порожній", systemImage: "list.bullet.rectangle") }
            }
            .navigationTitle("Лог операцій")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: OperationLog.fileURL) { Image(systemName: "square.and.arrow.up") }
                        .disabled(log.entries.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Очистити", role: .destructive) { log.clear() }
                }
            }
        }
    }

    private func color(_ level: OperationLog.Entry.Level) -> Color {
        switch level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
