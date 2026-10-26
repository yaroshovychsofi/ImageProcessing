import SwiftUI

struct FigureSymbolView: View {
    let figure: FigureClass
    var color = AppTheme.textPrimary

    var body: some View {
        Group {
            switch figure {
            case .circle:
                Circle()
                    .fill(color)
            case .square:
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
            case .triangle:
                TriangleShape()
                    .fill(color)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
