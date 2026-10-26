import SwiftUI

/// Shows what the network actually receives: the normalised figure reduced to 8x8 cell
/// intensities. Makes the preprocessing visible instead of leaving it a black box.
struct NetworkInputGridView: View {
    let cells: [Double]?
    var side = 8
    /// Definite size in points. The grid is built from flexible rectangles and has no
    /// intrinsic size of its own, so inside a vertical stack it would otherwise collapse.
    /// `nil` lets it fill the space it is offered, which is what the preview card wants.
    var size: Double?

    var body: some View {
        VStack(spacing: 10) {
            if let cells, cells.count == side * side {
                grid(cells)
                    .modifier(GridSize(size: size))
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .tint(AppTheme.accent)
                    .frame(height: 60)
            }

            Text("\(side) × \(side) — середня інтенсивність клітинок")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Вхід мережі: сітка \(side) на \(side) клітинок")
    }

    private func grid(_ cells: [Double]) -> some View {
        VStack(spacing: 1) {
            ForEach(0..<side, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<side, id: \.self) { column in
                        let intensity = cells[row * side + column]
                        Rectangle()
                            .fill(AppTheme.textPrimary.opacity(intensity))
                    }
                }
            }
        }
        .padding(6)
        .background(AppTheme.secondarySurface)
        .clipShape(.rect(cornerRadius: AppTheme.smallRadius))
    }
}

private struct GridSize: ViewModifier {
    let size: Double?

    func body(content: Content) -> some View {
        if let size {
            content.frame(width: size, height: size)
        } else {
            content
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
