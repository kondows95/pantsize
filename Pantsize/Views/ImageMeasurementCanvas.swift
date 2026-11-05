import SwiftUI

struct ImageMeasurementCanvas: View {
    let image: UIImage
    @Binding var measurements: [MeasurementItem]
    var activeID: UUID?
    var referenceID: UUID?
    var onUserInteraction: () -> Void = {}

    @State private var zoomResetToken = UUID()
    @State private var zoomScale: CGFloat = 1
    @State private var contentOffset: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                MeasurementScrollCanvas(
                    image: image,
                    viewSize: geo.size,
                    measurements: $measurements,
                    activeID: activeID,
                    referenceID: referenceID,
                    resetToken: zoomResetToken,
                    zoomScale: $zoomScale,
                    contentOffset: $contentOffset,
                    onUserInteraction: onUserInteraction
                )

                Button {
                    zoomScale = 1
                    contentOffset = .zero
                    zoomResetToken = UUID()
                } label: {
                    Label("1倍", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(8)
            }
        }
    }
}
