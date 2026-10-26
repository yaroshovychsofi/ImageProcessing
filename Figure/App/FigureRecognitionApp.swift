import SwiftUI

@main
struct FigureRecognitionApp: App {
    @State private var store = RecognitionStore()
    @State private var training = TrainingStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Розпізнавання", systemImage: "viewfinder") {
                    RecognitionScreen(store: store)
                }
                Tab("Навчання", systemImage: "brain") {
                    TrainingScreen(store: training)
                }
                Tab("Лог", systemImage: "list.bullet.rectangle") {
                    LogScreen()
                }
            }
            .tint(AppTheme.accent)
            .task {
                OperationLog.shared.add("Застосунок запущено. Зображень у Assets: \(TrainingDataset.images(in: Set(AssetGroup.allCases)).count).")
            }
            #if DEBUG
            .task {
                _ = await FixtureValidator.run()
            }
            #endif
        }
    }
}
