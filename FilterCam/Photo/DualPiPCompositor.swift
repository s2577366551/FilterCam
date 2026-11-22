import AVFoundation
import CoreImage

/// 双摄视频的自定义合成器：用 Core Image 把前摄小窗合成进去。
/// 这样圆角、投影、3:4 比例和拖动位置都和照片/预览完全一致。
final class DualPiPCompositor: NSObject, AVVideoCompositing {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? DualPiPInstruction else {
            request.finish(with: compositorError("合成指令无效"))
            return
        }
        guard let backBuffer = request.sourceFrame(byTrackID: instruction.backTrackID) else {
            request.finish(with: compositorError("缺少后摄画面"))
            return
        }

        let back = CIImage(cvPixelBuffer: backBuffer)
            .transformed(by: instruction.backTransform)
        let front = request.sourceFrame(byTrackID: instruction.frontTrackID).map {
            CIImage(cvPixelBuffer: $0).transformed(by: instruction.frontTransform)
        }

        let composed = PiPComposer.compose(
            back: back,
            front: front,
            center: instruction.pipCenter
        )

        guard let destination = request.renderContext.newPixelBuffer() else {
            request.finish(with: compositorError("无法创建视频帧"))
            return
        }
        let bounds = CGRect(origin: .zero, size: instruction.renderSize)
        context.render(composed, to: destination, bounds: bounds, colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: destination)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    private func compositorError(_ message: String) -> NSError {
        NSError(
            domain: "com.filtercam.compositor",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

/// 携带两条轨道、方向和 小窗位置的自定义合成指令。
final class DualPiPInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let backTrackID: CMPersistentTrackID
    let frontTrackID: CMPersistentTrackID
    let backTransform: CGAffineTransform
    let frontTransform: CGAffineTransform
    let pipCenter: CGPoint
    let renderSize: CGSize

    init(
        timeRange: CMTimeRange,
        backTrackID: CMPersistentTrackID,
        frontTrackID: CMPersistentTrackID,
        backTransform: CGAffineTransform,
        frontTransform: CGAffineTransform,
        pipCenter: CGPoint,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.backTrackID = backTrackID
        self.frontTrackID = frontTrackID
        self.backTransform = backTransform
        self.frontTransform = frontTransform
        self.pipCenter = pipCenter
        self.renderSize = renderSize
        self.requiredSourceTrackIDs = [
            NSNumber(value: backTrackID),
            NSNumber(value: frontTrackID)
        ]
        super.init()
    }
}
