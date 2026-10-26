import SwiftUI

struct RecognitionDestinationView: View {
    let route: RecognitionRoute
    let store: RecognitionStore

    var body: some View {
        switch route {
        case .history:
            HistoryScreen(store: store)
        case .detail(let record):
            RecognitionDetailScreen(record: record, store: store)
        }
    }
}
