import Metal

enum AppEnvironment {
    static func makeRenderer() -> PreviewRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return PreviewRenderer(device: device)
    }
}
