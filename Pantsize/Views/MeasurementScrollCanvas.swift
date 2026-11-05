import SwiftUI
import UIKit

struct MeasurementScrollCanvas: UIViewRepresentable {
    let image: UIImage
    let viewSize: CGSize
    @Binding var measurements: [MeasurementItem]
    let activeID: UUID?
    let referenceID: UUID?
    let resetToken: UUID
    @Binding var zoomScale: CGFloat
    @Binding var contentOffset: CGPoint
    var onUserInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        context.coordinator.buildScrollView(image: image, viewSize: viewSize)
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onUserInteraction = onUserInteraction
        context.coordinator.setMeasurements = { measurements = $0 }
        context.coordinator.zoomScaleBinding = { zoomScale = $0 }
        context.coordinator.contentOffsetBinding = { contentOffset = $0 }
        context.coordinator.mergePreservedScrollState(
            bindingZoom: zoomScale,
            bindingOffset: contentOffset,
            scrollView: scrollView
        )

        context.coordinator.render(
            image: image,
            viewSize: viewSize,
            measurements: measurements,
            activeID: activeID,
            referenceID: referenceID,
            resetToken: resetToken,
            scrollView: scrollView
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onUserInteraction: (() -> Void)?
        var setMeasurements: (([MeasurementItem]) -> Void)?
        var zoomScaleBinding: ((CGFloat) -> Void)?
        var contentOffsetBinding: ((CGPoint) -> Void)?

        private weak var scrollView: UIScrollView?
        private let contentView = UIView()
        private let imageView = UIImageView()
        /// 画像と同じ contentView 上に描画（ズーム・スクロールと一体）。
        private let linesContainer = UIView()
        private var handleViews: [HandleKey: EndpointHandleView] = [:]
        private var lastResetToken: UUID?
        private var lastViewSize: CGSize = .zero
        private var currentImage: UIImage = UIImage()
        /// レイアウト変動で scrollView の zoom が一瞬 1 倍になるのを防ぐ
        private var preservedZoomScale: CGFloat = 1
        private var preservedContentOffset: CGPoint = .zero
        /// relayoutPreservingZoom 中の setZoomScale(1) で preserved / Binding が上書きされないようにする
        private var isPreservingRelayout = false
        /// render / applyScrollState 中に delegate から SwiftUI を触らない
        private var suppressScrollStatePublish = false
        private var lastPublishedZoom: CGFloat = 1
        private var lastPublishedOffset: CGPoint = .zero

        func buildScrollView(image: UIImage, viewSize: CGSize) -> UIScrollView {
            currentImage = image

            let scrollView = UIScrollView()
            scrollView.delegate = self
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 8
            scrollView.bouncesZoom = true
            scrollView.alwaysBounceVertical = true
            scrollView.alwaysBounceHorizontal = true
            scrollView.showsVerticalScrollIndicator = true
            scrollView.showsHorizontalScrollIndicator = true
            scrollView.backgroundColor = UIColor.black.withAlphaComponent(0.92)
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delaysContentTouches = false

            contentView.backgroundColor = .clear
            scrollView.addSubview(contentView)

            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            contentView.addSubview(imageView)

            linesContainer.isUserInteractionEnabled = false
            linesContainer.backgroundColor = .clear
            contentView.addSubview(linesContainer)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            tap.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(tap)

            self.scrollView = scrollView
            layoutContent(size: viewSize)
            imageView.image = image

            return scrollView
        }

        func mergePreservedScrollState(
            bindingZoom: CGFloat,
            bindingOffset: CGPoint,
            scrollView: UIScrollView
        ) {
            let bestZoom = max(bindingZoom, preservedZoomScale, scrollView.zoomScale)
            if bestZoom > preservedZoomScale + 0.001 {
                preservedZoomScale = bestZoom
                if bindingZoom >= bestZoom - 0.001 {
                    preservedContentOffset = bindingOffset
                } else {
                    preservedContentOffset = scrollView.contentOffset
                }
            }
        }

        func render(
            image: UIImage,
            viewSize: CGSize,
            measurements: [MeasurementItem],
            activeID: UUID?,
            referenceID: UUID?,
            resetToken: UUID,
            scrollView: UIScrollView
        ) {
            latestActiveID = activeID
            latestReferenceID = referenceID
            latestMeasurements = measurements

            currentImage = image
            imageView.image = image

            let layoutSize = Self.validLayoutSize(viewSize, fallback: lastViewSize)
            guard layoutSize.width > 1, layoutSize.height > 1 else { return }

            latestViewSize = layoutSize

            if lastResetToken == nil {
                lastResetToken = resetToken
            } else if lastResetToken != resetToken {
                lastResetToken = resetToken
                preservedZoomScale = 1
                preservedContentOffset = .zero
                lastPublishedZoom = 1
                lastPublishedOffset = .zero
            }

            let viewSizeChanged = lastViewSize != layoutSize
            if viewSizeChanged {
                var targetOffset = preservedContentOffset
                if lastViewSize.width > 1, lastViewSize.height > 1 {
                    targetOffset = scaledContentOffset(
                        targetOffset,
                        from: lastViewSize,
                        to: layoutSize,
                        zoom: preservedZoomScale
                    )
                }
                relayoutPreservingZoom(
                    size: layoutSize,
                    scrollView: scrollView,
                    zoom: preservedZoomScale,
                    offset: targetOffset
                )
                lastViewSize = layoutSize
            } else {
                applyScrollState(
                    zoom: preservedZoomScale,
                    offset: preservedContentOffset,
                    scrollView: scrollView,
                    animated: false
                )
                syncPreservedFromScrollView(scrollView)
            }

            syncHandles(
                activeID: activeID,
                viewSize: layoutSize,
                scrollView: scrollView
            )
            redrawLines(in: scrollView)
        }

        private static func validLayoutSize(_ size: CGSize, fallback: CGSize) -> CGSize {
            if size.width > 1, size.height > 1 { return size }
            if fallback.width > 1, fallback.height > 1 { return fallback }
            return size
        }

        private func relayoutPreservingZoom(
            size: CGSize,
            scrollView: UIScrollView,
            zoom: CGFloat,
            offset: CGPoint
        ) {
            isPreservingRelayout = true
            defer { isPreservingRelayout = false }

            let clampedZoom = min(max(zoom, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            scrollView.setZoomScale(1, animated: false)
            layoutContent(size: size)
            scrollView.setZoomScale(clampedZoom, animated: false)
            let clampedOffset = clampContentOffset(offset, scrollView: scrollView)
            scrollView.setContentOffset(clampedOffset, animated: false)
            preservedZoomScale = scrollView.zoomScale
            preservedContentOffset = scrollView.contentOffset
        }

        private func syncPreservedFromScrollView(_ scrollView: UIScrollView) {
            guard !isPreservingRelayout else { return }
            preservedZoomScale = scrollView.zoomScale
            preservedContentOffset = scrollView.contentOffset
        }

        private func applyScrollState(
            zoom: CGFloat,
            offset: CGPoint,
            scrollView: UIScrollView,
            animated: Bool
        ) {
            suppressScrollStatePublish = true
            defer { suppressScrollStatePublish = false }

            let clampedZoom = min(max(zoom, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            if abs(scrollView.zoomScale - clampedZoom) > 0.001 {
                scrollView.setZoomScale(clampedZoom, animated: animated)
            }
            let clampedOffset = clampContentOffset(offset, scrollView: scrollView)
            if scrollView.contentOffset != clampedOffset {
                scrollView.setContentOffset(clampedOffset, animated: animated)
            }
        }

        private func clampContentOffset(_ offset: CGPoint, scrollView: UIScrollView) -> CGPoint {
            let viewport = scrollView.bounds.size
            let contentWidth = scrollView.contentSize.width
            let contentHeight = scrollView.contentSize.height
            let maxX = max(contentWidth - viewport.width, 0)
            let maxY = max(contentHeight - viewport.height, 0)
            return CGPoint(
                x: min(max(offset.x, 0), maxX),
                y: min(max(offset.y, 0), maxY)
            )
        }

        private func publishScrollState(from scrollView: UIScrollView) {
            guard !suppressScrollStatePublish, !isPreservingRelayout else { return }

            let zoom = preservedZoomScale
            let offset = preservedContentOffset
            guard abs(lastPublishedZoom - zoom) > 0.001
                || abs(lastPublishedOffset.x - offset.x) > 0.5
                || abs(lastPublishedOffset.y - offset.y) > 0.5 else { return }

            lastPublishedZoom = zoom
            lastPublishedOffset = offset

            let publishZoom = zoomScaleBinding
            let publishOffset = contentOffsetBinding
            DispatchQueue.main.async {
                publishZoom?(zoom)
                publishOffset?(offset)
            }
        }

        private func layoutContent(size: CGSize) {
            guard let scrollView else { return }
            contentView.frame = CGRect(origin: .zero, size: size)
            imageView.frame = contentView.bounds
            linesContainer.frame = contentView.bounds
            scrollView.contentSize = size
        }

        /// キャンバスサイズ変更後も同じ位置が見えるよう contentOffset をスケールする。
        private func scaledContentOffset(
            _ offset: CGPoint,
            from oldSize: CGSize,
            to newSize: CGSize,
            zoom: CGFloat
        ) -> CGPoint {
            let scaleX = newSize.width / oldSize.width
            let scaleY = newSize.height / oldSize.height
            var scaled = CGPoint(x: offset.x * scaleX, y: offset.y * scaleY)

            guard let scrollView else { return scaled }

            let viewport = scrollView.bounds.size
            let contentWidth = newSize.width * zoom
            let contentHeight = newSize.height * zoom
            let maxX = max(contentWidth - viewport.width, 0)
            let maxY = max(contentHeight - viewport.height, 0)
            scaled.x = min(max(scaled.x, 0), maxX)
            scaled.y = min(max(scaled.y, 0), maxY)
            return scaled
        }

        private func displayRect(viewSize: CGSize) -> CGRect {
            ImageCoordinateMapper.displayRect(imageSize: currentImage.size, in: viewSize)
        }

        private func redrawLines(in scrollView: UIScrollView) {
            linesContainer.frame = contentView.bounds
            linesContainer.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

            let rect = displayRect(viewSize: latestViewSize)
            let zoom = max(scrollView.zoomScale, 1)
            let lineWidth = MeasurementLineStyle.screenWidth / zoom
            let dashOn = MeasurementLineStyle.dashOnScreen / zoom
            let dashOff = MeasurementLineStyle.dashOffScreen / zoom
            let dotR = MeasurementLineStyle.dotRadiusScreen / zoom
            let tipR = MeasurementLineStyle.tipRadiusScreen / zoom
            let tipStroke = MeasurementLineStyle.tipStrokeScreen / zoom

            for (index, item) in latestMeasurements.enumerated() {
                let color = UIColor(MeasurementPalette.color(at: index + 1))
                let isActive = item.id == latestActiveID
                let strokeAlpha: CGFloat = isActive ? 1 : 0.55

                if let start = item.line.viewPoint(for: .start, displayRect: rect),
                   let end = item.line.viewPoint(for: .end, displayRect: rect) {
                    let path = UIBezierPath()
                    path.move(to: start)
                    path.addLine(to: end)

                    let layer = CAShapeLayer()
                    layer.path = path.cgPath
                    layer.strokeColor = color.withAlphaComponent(strokeAlpha).cgColor
                    layer.lineWidth = lineWidth
                    layer.lineCap = .butt
                    layer.lineDashPattern = [NSNumber(value: dashOn), NSNumber(value: dashOff)]
                    layer.fillColor = nil
                    linesContainer.layer.addSublayer(layer)

                    if !isActive {
                        addLineEndpointTips(
                            at: [start, end],
                            color: color,
                            fillAlpha: strokeAlpha,
                            radius: tipR,
                            strokeWidth: tipStroke,
                            to: linesContainer.layer
                        )
                    }
                } else if let start = item.line.viewPoint(for: .start, displayRect: rect) {
                    let dot = CAShapeLayer()
                    dot.path = UIBezierPath(
                        ovalIn: CGRect(x: start.x - dotR, y: start.y - dotR, width: dotR * 2, height: dotR * 2)
                    ).cgPath
                    dot.fillColor = color.cgColor
                    linesContainer.layer.addSublayer(dot)
                }
            }
        }

        private func addLineEndpointTips(
            at points: [CGPoint],
            color: UIColor,
            fillAlpha: CGFloat,
            radius: CGFloat,
            strokeWidth: CGFloat,
            to parent: CALayer
        ) {
            for point in points {
                let tip = CAShapeLayer()
                tip.path = UIBezierPath(
                    ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                ).cgPath
                tip.fillColor = color.withAlphaComponent(fillAlpha).cgColor
                tip.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
                tip.lineWidth = strokeWidth
                parent.addSublayer(tip)
            }
        }

        private func syncHandles(
            activeID: UUID?,
            viewSize: CGSize,
            scrollView: UIScrollView
        ) {
            var needed = Set<HandleKey>()
            let bounds = displayRect(viewSize: viewSize)

            if let activeID,
               let item = latestMeasurements.first(where: { $0.id == activeID }),
               let index = latestMeasurements.firstIndex(where: { $0.id == activeID }) {
                let color = UIColor(MeasurementPalette.color(at: index + 1))

                if let start = item.line.viewPoint(for: .start, displayRect: bounds) {
                    needed.insert(HandleKey(id: activeID, endpoint: .start))
                    attachHandle(
                        key: HandleKey(id: activeID, endpoint: .start),
                        point: start,
                        color: color,
                        label: "始",
                        bounds: bounds,
                        scrollView: scrollView
                    )
                }
                if let end = item.line.viewPoint(for: .end, displayRect: bounds) {
                    needed.insert(HandleKey(id: activeID, endpoint: .end))
                    attachHandle(
                        key: HandleKey(id: activeID, endpoint: .end),
                        point: end,
                        color: color,
                        label: "終",
                        bounds: bounds,
                        scrollView: scrollView
                    )
                }
            }

            for (key, view) in handleViews where !needed.contains(key) {
                view.removeFromSuperview()
                handleViews.removeValue(forKey: key)
            }

            if let activeID {
                applyOverlapHandleSeparation(activeID: activeID, scrollView: scrollView)
            }
        }

        private func attachHandle(
            key: HandleKey,
            point: CGPoint,
            color: UIColor,
            label: String,
            bounds: CGRect,
            scrollView: UIScrollView
        ) {
            let handle = handleViews[key] ?? EndpointHandleView(label: label)
            handle.scrollView = scrollView
            handle.contentView = contentView
            handle.color = color
            handle.contentBounds = bounds
            if !handle.isDragging {
                handle.contentPoint = point
            }
            handle.onDragChanged = { [weak self] newPoint in
                guard let self, let scrollView = self.scrollView else { return }
                self.applyLiveEndpoint(key: key, viewPoint: newPoint)
                self.positionHandle(handle, in: scrollView)
                self.redrawLines(in: scrollView)
            }
            handle.onDragEnded = { [weak self] newPoint in
                guard let self, let scrollView = self.scrollView else { return }
                self.updateEndpoint(key: key, viewPoint: newPoint)
                if let activeID = self.latestActiveID {
                    self.applyOverlapHandleSeparation(activeID: activeID, scrollView: scrollView)
                }
            }
            handleViews[key] = handle
            if handle.superview !== scrollView {
                scrollView.addSubview(handle)
            }
            positionHandle(handle, in: scrollView)
            scrollView.bringSubviewToFront(handle)
        }

        private func positionHandle(_ handle: EndpointHandleView, in scrollView: UIScrollView) {
            var center = scrollView.convert(handle.contentPoint, from: contentView)
            if !handle.isDragging {
                center.x += handle.screenLayoutOffset.x
                center.y += handle.screenLayoutOffset.y
            }
            handle.center = center
        }

        /// 始点・終点が重なったとき、画面上だけハンドルを少し離して両方つかめるようにする。
        private func applyOverlapHandleSeparation(activeID: UUID, scrollView: UIScrollView) {
            let startKey = HandleKey(id: activeID, endpoint: .start)
            let endKey = HandleKey(id: activeID, endpoint: .end)
            guard let startHandle = handleViews[startKey], let endHandle = handleViews[endKey] else { return }
            if startHandle.isDragging || endHandle.isDragging { return }

            let zoom = max(scrollView.zoomScale, 1)
            let mergeThreshold = 8 / zoom
            let dx = endHandle.contentPoint.x - startHandle.contentPoint.x
            let dy = endHandle.contentPoint.y - startHandle.contentPoint.y
            let distance = hypot(dx, dy)

            guard distance < mergeThreshold else {
                startHandle.screenLayoutOffset = .zero
                endHandle.screenLayoutOffset = .zero
                positionHandle(startHandle, in: scrollView)
                positionHandle(endHandle, in: scrollView)
                return
            }

            let separation: CGFloat = 12
            var nx: CGFloat
            var ny: CGFloat
            if distance > 0.001 {
                nx = -dy / distance
                ny = dx / distance
            } else {
                let d = CGFloat(2).squareRoot()
                nx = 1 / d
                ny = -1 / d
            }

            startHandle.screenLayoutOffset = CGPoint(x: -nx * separation, y: -ny * separation)
            endHandle.screenLayoutOffset = CGPoint(x: nx * separation, y: ny * separation)
            positionHandle(startHandle, in: scrollView)
            positionHandle(endHandle, in: scrollView)
            scrollView.bringSubviewToFront(startHandle)
            scrollView.bringSubviewToFront(endHandle)
        }

        private func updateAllHandlePositions() {
            guard let scrollView else { return }
            for handle in handleViews.values {
                positionHandle(handle, in: scrollView)
            }
        }

        private func applyLiveEndpoint(key: HandleKey, viewPoint: CGPoint) {
            guard let index = latestMeasurements.firstIndex(where: { $0.id == key.id }) else { return }
            let rect = displayRect(viewSize: latestViewSize)
            latestMeasurements[index].line.setViewPoint(viewPoint, for: key.endpoint, displayRect: rect)
        }

        private func updateEndpoint(key: HandleKey, viewPoint: CGPoint) {
            onUserInteraction?()
            let rect = displayRect(viewSize: latestViewSize)
            updateMeasurements { items in
                guard let index = items.firstIndex(where: { $0.id == key.id }) else { return }
                items[index].line.setViewPoint(viewPoint, for: key.endpoint, displayRect: rect)
            }
        }

        private var latestMeasurements: [MeasurementItem] = []

        private func updateMeasurements(_ mutate: (inout [MeasurementItem]) -> Void) {
            var items = latestMeasurements
            mutate(&items)
            latestMeasurements = items
            if let scrollView {
                syncHandles(
                    activeID: latestActiveID,
                    viewSize: latestViewSize,
                    scrollView: scrollView
                )
                redrawLines(in: scrollView)
            }
            let apply = setMeasurements
            DispatchQueue.main.async {
                apply?(items)
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let scrollView else { return }
            onUserInteraction?()

            let location = recognizer.location(in: contentView)
            let rect = displayRect(viewSize: latestViewSize)
            guard rect.contains(location) else { return }

            guard let activeID = latestActiveID,
                  let index = latestMeasurements.firstIndex(where: { $0.id == activeID }) else { return }

            let zoom = max(scrollView.zoomScale, 1)
            let threshold = PointSnap.threshold / zoom
            var line = latestMeasurements[index].line

            guard !line.isComplete else { return }

            let anchors = PointSnap.viewAnchors(from: latestMeasurements, displayRect: rect)
            let excludingStart = line.start == nil
                ? nil
                : line.viewPoint(for: .start, displayRect: rect)
            let adjusted = PointSnap.snap(
                location,
                anchors: anchors,
                excluding: excludingStart,
                threshold: threshold
            )

            if line.start == nil {
                line.setViewPoint(adjusted, for: .start, displayRect: rect)
            } else if line.end == nil {
                line.setViewPoint(adjusted, for: .end, displayRect: rect)
            }
            updateMeasurements { items in
                guard let i = items.firstIndex(where: { $0.id == activeID }) else { return }
                items[i].line = line
            }
        }

        private var latestActiveID: UUID?
        private var latestReferenceID: UUID?
        private var latestViewSize: CGSize = .zero

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncPreservedFromScrollView(scrollView)
            if !isPreservingRelayout {
                publishScrollState(from: scrollView)
            }
            updateAllHandlePositions()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            if isPreservingRelayout {
                updateAllHandlePositions()
                return
            }
            syncPreservedFromScrollView(scrollView)
            publishScrollState(from: scrollView)
            updateAllHandlePositions()
            redrawLines(in: scrollView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !(touch.view is EndpointHandleView)
        }
    }
}

private enum MeasurementLineStyle {
    /// 画面上の見た目（pt）。アクティブ/非アクティブで太さは変えない（端点ズレ防止）。
    static let screenWidth: CGFloat = 1.5
    static let dashOnScreen: CGFloat = 5
    static let dashOffScreen: CGFloat = 4
    static let dotRadiusScreen: CGFloat = 4
    /// 非アクティブ線の端点マーカー（ハンドルより小さく）
    static let tipRadiusScreen: CGFloat = 2.5
    static let tipStrokeScreen: CGFloat = 0.75
}

private struct HandleKey: Hashable {
    let id: UUID
    let endpoint: LineEndpoint
}

private final class EndpointHandleView: UIView {
    weak var scrollView: UIScrollView?
    weak var contentView: UIView?

    var contentPoint: CGPoint = .zero
    /// 端点が重なったときの表示用オフセット（scrollView 座標・pt）
    var screenLayoutOffset: CGPoint = .zero
    var contentBounds: CGRect = .zero
    var color: UIColor = .cyan { didSet { setNeedsDisplay() } }
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    private(set) var isDragging = false

    private let label: String
    private var panStartContentPoint: CGPoint = .zero

    init(label: String) {
        self.label = label
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        backgroundColor = .clear
        isUserInteractionEnabled = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44))

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attrs
        )
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let scrollView, let contentView else { return }

        switch recognizer.state {
        case .began:
            isDragging = true
            panStartContentPoint = contentPoint
        case .changed:
            let translation = recognizer.translation(in: scrollView)
            let zoom = max(scrollView.zoomScale, 1)
            var next = CGPoint(
                x: panStartContentPoint.x + translation.x / zoom,
                y: panStartContentPoint.y + translation.y / zoom
            )
            next = clamp(next, to: contentBounds)
            contentPoint = next
            center = scrollView.convert(next, from: contentView)
            onDragChanged?(contentPoint)
        case .ended, .cancelled:
            isDragging = false
            screenLayoutOffset = .zero
            onDragEnded?(contentPoint)
        default:
            break
        }
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}
