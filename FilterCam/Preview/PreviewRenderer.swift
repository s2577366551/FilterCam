import CoreImage
import MetalKit

final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let context: CIContext
    private let commandQueue: MTLCommandQueue?
    private let lock = NSLock()
    private var latest: CIImage?

    var onNeedsDisplay: (() -> Void)?

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .cacheIntermediates: false
        ])
        super.init()
    }

    func submit(_ image: CIImage) {
        lock.lock()
        latest = image
        lock.unlock()
        onNeedsDisplay?()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else {
            return
        }
        lock.lock()
        let image = latest
        lock.unlock()
        guard let image else { return }

        let bounds = CGRect(origin: .zero, size: view.drawableSize)
        let transform = AspectFill.transform(contentSize: image.extent.size, in: bounds)
        let output = image.transformed(by: transform)
        context.render(
            output,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
