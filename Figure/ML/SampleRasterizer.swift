import SwiftUI

/// The built-in examples are drawn by SwiftUI rather than stored as files, so they have to be
/// rasterised before recognition. The layout imitates the training images: a dark figure on a
/// white background occupying roughly 55% of the frame.
@MainActor
enum SampleRasterizer {
    static let side: CGFloat = 256
    static let figureScale: CGFloat = 0.55

    static func render(_ figure: FigureClass) -> CGImage? {
        let renderer = ImageRenderer(
            content: ZStack {
                Color.white
                FigureSymbolView(figure: figure, color: .black)
                    .frame(width: side * figureScale, height: side * figureScale)
            }
            .frame(width: side, height: side)
        )
        renderer.scale = 1
        return renderer.cgImage
    }
}
