import CoreGraphics

enum AspectFill {
    static func transform(contentSize: CGSize, in bounds: CGRect) -> CGAffineTransform {
        guard contentSize.width > 0, contentSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return .identity
        }
        let scale = max(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let scaled = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        let dx = bounds.midX - scaled.width / 2
        let dy = bounds.midY - scaled.height / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }
}
