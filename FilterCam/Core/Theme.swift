import SwiftUI

enum Theme {
    static let background = Color.black
    static let control = Color.white.opacity(0.9)
    static let controlDim = Color.white.opacity(0.55)
    static let overlay = Color.black.opacity(0.45)
    static let cornerRadius: CGFloat = 8
    static let hitTarget: CGFloat = 44

    /// MUJI 字号体系：正文 16 / 说明 14 / 小字 12 / 标题 26 / 大标题 32。
    enum Font {
        static let largeTitle: CGFloat = 32
        static let title: CGFloat = 26
        static let body: CGFloat = 16
        static let caption: CGFloat = 14
        static let small: CGFloat = 12

        /// 图标尺寸跟着字号走：正文 20、说明 18、小字 16。
        static let iconBody: CGFloat = 20
        static let iconCaption: CGFloat = 18
        static let iconSmall: CGFloat = 16
    }
}
