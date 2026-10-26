import Charts
import SwiftUI

struct TrainingScreen: View {
    @Bindable var store: TrainingStore
    @State private var exportURLs: [URL] = []

    var body: some View {
        NavigationStack {
            Form {
                dataSection
                parametersSection
                controlSection
                if store.phase != .idle { progressSection }
                if !store.history.isEmpty { chartSection }
                if let result = store.result { resultSection(result) }
                benchmarkSection
                modelSection
            }
            .navigationTitle("Навчання")
            .disabled(false)
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            ForEach(AssetGroup.allCases) { group in
                Toggle(isOn: binding(for: group)) {
                    VStack(alignment: .leading) {
                        Text(group.title)
                        Text("Assets/\(group.rawValue) · \(TrainingDataset.count(in: group)) зображень")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Stepper(value: $store.imageLimit, in: 30...max(30, store.availableImages), step: store.imageLimit < 600 ? 30 : 300) {
                LabeledContent("Кількість зображень", value: "\(min(store.imageLimit, store.availableImages)) з \(store.availableImages)")
            }
            Stepper(value: $store.testFraction, in: 0.1...0.5, step: 0.05) {
                LabeledContent("Тестова вибірка", value: "\(Int((store.testFraction * 100).rounded())) %")
            }
        } header: {
            Text("Дані")
        } footer: {
            Text("Оберіть усю папку Assets (обидва перемикачі) або окрему групу за якістю зображень.")
        }
        .disabled(store.isRunning)
    }

    private func binding(for group: AssetGroup) -> Binding<Bool> {
        Binding {
            store.groups.contains(group)
        } set: { isOn in
            if isOn { store.groups.insert(group) } else { store.groups.remove(group) }
            store.imageLimit = min(max(store.imageLimit, 30), max(30, store.availableImages))
        }
    }

    // MARK: Parameters

    private var parametersSection: some View {
        Section("Параметри мережі Brain.js") {
            Stepper(value: $store.config.epochs, in: 1...3000, step: store.config.epochs < 100 ? 10 : 50) {
                LabeledContent("Кількість епох", value: "\(store.config.epochs)")
            }
            VStack(alignment: .leading) {
                LabeledContent("Швидкість навчання", value: String(format: "%.3f", store.config.learningRate))
                Slider(value: $store.config.learningRate, in: 0.001...1, step: 0.001)
            }
            VStack(alignment: .leading) {
                LabeledContent("Momentum", value: String(format: "%.2f", store.config.momentum))
                Slider(value: $store.config.momentum, in: 0...0.99, step: 0.01)
            }
            Stepper(value: $store.config.hiddenNeurons, in: 2...64) {
                LabeledContent("Нейронів у прихованому шарі", value: "\(store.config.hiddenNeurons)")
            }
            Picker("Цільова помилка (errorThresh)", selection: $store.config.errorThresh) {
                ForEach([0.05, 0.01, 0.005, 0.001, 0.0001], id: \.self) { Text(String($0)).tag($0) }
            }
            Toggle("Паралельна обробка (\(ParallelFeatureExtractor.coreCount) ядер)", isOn: $store.parallel)
        }
        .disabled(store.isRunning)
    }

    private var controlSection: some View {
        Section {
            if store.isRunning {
                Button(role: .destructive) { store.stop() } label: {
                    Label("Зупинити", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
            } else {
                Button { exportURLs = []; store.start() } label: {
                    Label("Навчити мережу", systemImage: "brain").frame(maxWidth: .infinity)
                }
                .disabled(store.groups.isEmpty || store.isBenchmarking)
            }
        }
    }

    // MARK: Progress

    private var progressSection: some View {
        Section {
            Text(store.phase.title).font(.headline)
            ProgressView(value: store.extractionFraction) {
                LabeledContent("1. Обробка зображень", value: "\(store.processed) / \(store.toProcess) · \(Int(store.extractionFraction * 100)) %")
            }
            ProgressView(value: store.epochFraction) {
                LabeledContent("2. Епоха", value: "\(store.epoch) / \(store.config.epochs)")
            }
            if let error = store.currentError {
                LabeledContent("Поточна помилка", value: String(format: "%.5f", error))
            }
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                LabeledContent("Загальний час", value: elapsed)
            }
            if let time = store.extractionTime { LabeledContent("Обробка зображень", value: time.formattedSeconds) }
            if let time = store.trainingTime {
                LabeledContent("Навчання", value: time.formattedSeconds)
                if store.epoch > 0 {
                    LabeledContent("На одну епоху", value: String(format: "%.1f мс", time.seconds / Double(store.epoch) * 1000))
                }
            }
        } header: { Text("Хід виконання") }
    }

    private var elapsed: String {
        if let total = store.result?.totalTime { return total.formattedSeconds }
        guard let started = store.startedAt else { return "—" }
        let end = store.endedAt ?? .now
        return String(format: "%.2f с", end.timeIntervalSince(started))
    }

    // MARK: Chart

    private var chartSection: some View {
        Section("Графік навчання") {
            TrainingChart(history: store.history).frame(height: 220)
        }
    }

    // MARK: Result

    private func resultSection(_ result: TrainingResult) -> some View {
        Section {
            LabeledContent("Точність на навчальній", value: percent(result.trainAccuracy))
            LabeledContent("Точність на тестовій", value: percent(result.testAccuracy)).bold()
            if let bundled = result.bundledTestAccuracy {
                LabeledContent("Вбудована модель на цих же тестових", value: percent(bundled))
            }
            LabeledContent("Зображень train / test", value: "\(result.trainCount) / \(result.testCount)")
            LabeledContent("Епох виконано", value: "\(result.epochsDone)")
            LabeledContent("Кінцева помилка", value: String(format: "%.5f", result.finalError))
            ConfusionMatrixView(confusion: result.confusion)
            if !result.misclassified.isEmpty {
                VStack(alignment: .leading) {
                    Text("Помилково розпізнані (\(result.misclassified.count))").font(.subheadline.bold())
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(result.misclassified.prefix(20)) { item in
                                MisclassifiedThumbnail(item: item)
                            }
                        }
                    }
                }
            }
            if store.resultApplied {
                Label("Модель застосовано для розпізнавання", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await store.applyTrainedModel() }
                } label: {
                    Label("Застосувати цю модель для розпізнавання", systemImage: "checkmark.circle")
                }
            }
            if exportURLs.isEmpty {
                Button { exportURLs = prepareExport() } label: {
                    Label("Зберегти результат", systemImage: "square.and.arrow.down")
                }
            } else {
                ShareLink(items: exportURLs) {
                    Label("Поділитися: модель, CSV, звіт, графік", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Результат")
        } footer: {
            Text(store.resultApplied
                 ? "Вкладка «Розпізнавання» тепер використовує цю модель."
                 : "Поки модель не застосовано, вкладка «Розпізнавання» використовує попередню модель. Вбудована модель навчена на ~18 000 зображень, тому зазвичай точніша.")
        }
    }

    private func prepareExport() -> [URL] {
        var urls = store.exportFiles()
        let renderer = ImageRenderer(content: TrainingChart(history: store.history).frame(width: 800, height: 400).padding().background(.white))
        renderer.scale = 2
        if let image = renderer.uiImage, let data = image.pngData(), let folder = urls.first?.deletingLastPathComponent() {
            let url = folder.appending(path: "training-chart.png")
            if (try? data.write(to: url)) != nil { urls.append(url) }
        }
        return urls
    }

    // MARK: Benchmark

    private var benchmarkSection: some View {
        Section {
            Button {
                Task { await store.runBenchmark() }
            } label: {
                Label("Порівняти 1 потік і \(ParallelFeatureExtractor.coreCount) потоків", systemImage: "speedometer")
            }
            .disabled(store.isRunning || store.isBenchmarking || store.groups.isEmpty)
            if store.isBenchmarking {
                ProgressView(value: Double(store.benchmarkProcessed), total: Double(max(1, store.benchmarkTotal))) {
                    Text("Оброблено \(store.benchmarkProcessed) / \(store.benchmarkTotal)")
                }
            }
            if let benchmark = store.benchmark {
                LabeledContent("Зображень", value: "\(benchmark.images)")
                LabeledContent("1 потік", value: benchmark.sequential.formattedSeconds)
                LabeledContent("\(benchmark.workers) потоків", value: benchmark.parallel.formattedSeconds)
                LabeledContent("Прискорення", value: String(format: "×%.2f", benchmark.speedup)).bold()
            }
        } header: {
            Text("Розпаралелення")
        } footer: {
            Text("Обробка кожного зображення незалежна, тому виконується в TaskGroup — по одному завданню на ядро.")
        }
    }

    private var modelSection: some View {
        Section("Модель") {
            LabeledContent("Активна модель", value: store.usesTrainedModel ? "навчена в застосунку" : "вбудована")
            if store.usesTrainedModel {
                Button("Повернути вбудовану модель", role: .destructive) {
                    Task { await store.resetModel() }
                }
                .disabled(store.isRunning)
            }
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.2f %%", value * 100) }
}

struct TrainingChart: View {
    let history: [EpochPoint]

    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(x: .value("Епоха", point.epoch), y: .value("Значення", point.error), series: .value("Ряд", "Помилка"))
                    .foregroundStyle(by: .value("Ряд", "Помилка"))
            }
            ForEach(history.filter { $0.testAccuracy != nil }) { point in
                LineMark(x: .value("Епоха", point.epoch), y: .value("Значення", point.testAccuracy ?? 0), series: .value("Ряд", "Точність test"))
                    .foregroundStyle(by: .value("Ряд", "Точність test"))
                LineMark(x: .value("Епоха", point.epoch), y: .value("Значення", point.trainAccuracy ?? 0), series: .value("Ряд", "Точність train"))
                    .foregroundStyle(by: .value("Ряд", "Точність train"))
            }
        }
        .chartYScale(domain: 0...1)
        .chartXAxisLabel("Епоха")
    }
}

struct ConfusionMatrixView: View {
    let confusion: [[Int]]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Матриця помилок (рядок — правильний клас, стовпець — відповідь)").font(.caption).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(FigureClass.allCases) { Text($0.title).font(.caption.bold()) }
                }
                ForEach(Array(FigureClass.allCases.enumerated()), id: \.offset) { row, figure in
                    GridRow {
                        Text(figure.title).font(.caption.bold())
                        ForEach(0..<3, id: \.self) { column in
                            Text("\(confusion[row][column])")
                                .monospacedDigit()
                                .frame(minWidth: 44, minHeight: 28)
                                .background(row == column ? Color.green.opacity(0.2) : (confusion[row][column] > 0 ? Color.red.opacity(0.15) : Color.clear),
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }
}

private struct MisclassifiedThumbnail: View {
    let item: MisclassifiedImage

    var body: some View {
        VStack(spacing: 2) {
            if let image = TrainingDataset.loadImage(item.url) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit().frame(width: 64, height: 64)
            }
            Text("\(FigureClass.allCases[item.expected].title) → \(FigureClass.allCases[item.predicted].title)")
                .font(.caption2)
        }
    }
}
