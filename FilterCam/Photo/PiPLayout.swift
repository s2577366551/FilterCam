import CoreImage
import UIKit

/// 前后双摄的画中画布局：后摄铺满，前摄贴在右上角。
enum PiPLayout {
    /// 小窗占主画面的宽度比例。
    static let widthRatio: CGFloat = 0.30

    /// Core Image 坐标系（原点左下、y 向上），所以「右上角」用 maxY。
    static func insetRect(in frame: CGRect, aspect: CGFloat) -> CGRect {
        let width = frame.width * widthRatio
        let height = width / max(aspect, 0.1)
        let margin = frame.width * 0.035
        return CGRect(
            x: frame.maxX - width - margin,
            y: frame.maxY - height - margin,
            width: width,
            height: height
        )
    }

    /// 把内容等比放大到填满目标矩形（居中裁切）。
    static func fillTransform(content: CGRect, into rect: CGRect) -> CGAffineTransform {
        guard content.width > 0, content.height > 0 else { return .identity }
        let scale = max(rect.width / content.width, rect.height / content.height)
        let tx = rect.midX - (content.midX * scale)
        let ty = rect.midY - (content.midY * scale)
        return CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale)
    }
}

/// 把后摄画面和前摄小窗合成一张图，预览和拍照共用。
enum PiPComposer {
    static func compose(back: CIImage, front: CIImage?, aspect: CGFloat) -> CIImage {
        guard let front else { return back }
        let frame = back.extent
        guard frame.width > 0, frame.height > 0 else { return back }

        let inset = PiPLayout.insetRect(in: frame, aspect: aspect)
        let radius = inset.width * 0.09
        let scaled = front
            .transformed(by: PiPLayout.fillTransform(content: front.extent, into: inset))
            .cropped(to: inset)

        let rounded = rounded(scaled, rect: inset, radius: radius)
        // 不要白边，用一层很淡的柔和阴影把画面托起来。
        let shadow = softShadow(rect: inset, radius: radius, frame: frame)
        return rounded.composited(over: shadow.composited(over: back))
    }

    /// 给前摄小窗加圆角，接近视频通话的画中画。
    private static func rounded(_ image: CIImage, rect: CGRect, radius: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CIRoundedRectangleGenerator") else { return image }
        filter.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(CIColor.white, forKey: "inputColor")
        guard let mask = filter.outputImage else { return image }
        return image.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputMaskImageKey: mask,
                kCIInputBackgroundImageKey: CIImage.empty()
            ]
        )
    }

    /// 半透明黑色圆角矩形 + 高斯模糊，作为小窗的柔和投影。
    private static func softShadow(rect: CGRect, radius: CGFloat, frame: CGRect) -> CIImage {
        let blur = max(frame.width * 0.008, 4)
        let offset = max(frame.width * 0.004, 2)
        let shadowRect = rect.offsetBy(dx: 0, dy: -offset)
        let padded = shadowRect.insetBy(dx: -blur * 2, dy: -blur * 2)

        guard let filter = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return CIImage.empty()
        }
        filter.setValue(CIVector(cgRect: padded), forKey: "inputExtent")
        filter.setValue(radius + blur, forKey: "inputRadius")
        filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0.30), forKey: "inputColor")
        guard let base = filter.outputImage?.cropped(to: padded) else {
            return CIImage.empty()
        }
        return base
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
            .cropped(to: frame)
    }
}
