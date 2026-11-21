import MetalKit
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = renderer
        view.backgroundColor = .black
        renderer.onNeedsDisplay = { [weak view] in
            DispatchQueue.main.async {
                view?.setNeedsDisplay()
            }
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
