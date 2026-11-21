# FilterCam 设计文档

- 日期：2026-11-21
- 状态：已确认（v2 范围：胶片滤镜 + Q 版贴纸）
- 类型：全新项目（iOS App）

## 1. 背景与目标

做一款 iOS 相机 App：拍出的照片有**日本富士胶片**的画质质感（Classic Chrome、Classic Neg、Acros 等胶片模拟的色彩、颗粒、暗部偏色），并能把照片里的主体**离线生成 Q 版漫画风贴纸**，手动摆放后导出成片。

约束条件：

- 开发者只有 Windows 电脑，没有 Mac。
- 开发由 AI 完成，用户负责提供账号/设备、真机试用和反馈。
- 用户有较新的 iPhone 真机，可用于测试。
- 用户有编程基础，但没写过 iOS。

因此项目除产品设计外，还必须解决"没有 Mac 如何编译并安装到 iPhone"的问题。

## 2. 范围

### v1 做

- 实时胶片滤镜预览（42 款滤镜 + 原图，分 5 类）
- 滤镜强度调节（0–100%）
- **滤镜参数微调**：曝光、对比度、色温、颗粒
- 滤镜库：分类浏览、收藏、最近使用
- 拍照，全分辨率套用当前滤镜
- **胶片边框**：135 齿孔、拍立得白边、宽幅留白
- **内置贴纸库**：取景器装饰贴纸 + 可摆放到成片上的贴纸
- **Q 版贴纸生成**：对照片主体做动漫化、抠图、白描边，生成可摆放的贴纸
- **贴纸编辑**：拖动、缩放、旋转、删除
- 导出合成图到系统相册
- 前后摄像头切换、闪光灯三态
- 相机/相册权限处理与引导
- 会话中断恢复、竖屏锁定

### v1 不做

- 视频录制
- 美颜（磨皮、瘦脸、美白）
- 云端 AI 生图、文字生成贴纸
- 手写文字、完整拼贴模板系统
- 社交分享、账号、云同步
- 除模型下载外的任何网络请求

以上不做项不预留代码，只保证模块边界清晰，后续可扩展。

## 3. 技术路线

| 项目 | 选择 |
|---|---|
| 语言 | Swift 5.9+ |
| UI | SwiftUI，取景器用 UIKit 桥接 |
| 相机 | AVFoundation |
| 滤镜 | Core Image + 3D LUT（CIColorCubeWithColorSpace） |
| 预览渲染 | MTKView + CIContext(mtlDevice:) |
| 贴纸风格化 | Core ML 模型（动漫化），Neural Engine 推理 |
| 主体抠图 | Vision `VNGenerateForegroundInstanceMaskRequest`（iOS 17） |
| 人脸关键点 | Vision `VNDetectFaceLandmarksRequest`（用于轻度夸张） |
| 照片保存 | Photos 框架 |
| 最低系统 | iOS 17.0 |
| 工程生成 | XcodeGen（`project.yml`） |
| 构建 | GitHub Actions `macos-15` + Xcode 16.x |
| 安装 | 未签名 IPA → Windows 端 Sideloadly + 用户 Apple ID |
| 第三方运行时依赖 | 无（仅一个随包 Core ML 模型文件） |

关键取舍：

- 富士色彩不公开，用 3D LUT 逼近，这是业界标准做法。
- 端侧生成只做"动漫化 + 抠图 + 白边 + 轻度夸张"，不做生成式重绘（端侧跑不动）。
- 模型转换在 CI 的 macOS 机器上完成，因为 coremltools 在 Windows 上不可靠。

## 4. 架构

### 4.1 分层

```
┌──────────────────────────────────────────────┐
│ UI 层（SwiftUI）                               │
│ CameraScreen / EditorScreen / FilterStrip     │
└───────────────┬──────────────────────────────┘
                │ 只依赖 ViewModel 与协议
┌───────────────▼──────────────────────────────┐
│ ViewModel                                     │
│ CameraViewModel / EditorViewModel             │
└───┬───────────┬───────────────┬──────────────┘
    │           │               │
┌───▼─────┐ ┌───▼────────┐ ┌────▼──────────────┐
│ Camera  │ │ Filter     │ │ Sticker           │
│ Service │ │ Pipeline   │ │ Generator         │
│AVFound. │ │Core Image  │ │Core ML + Vision   │
└───┬─────┘ └───┬────────┘ └────┬──────────────┘
    │  CIImage  │ CIImage       │ CGImage + mask
┌───▼───────────▼───────────────▼──────────────┐
│ Renderer / Composer（Core Image + Metal）      │
│ 实时预览渲染、贴纸图层合成、导出               │
└──────────────────────────────────────────────┘
```

规则：

- UI 层不得直接 import AVFoundation、Core Image、Core ML、Vision。
- `CameraService` 不知道滤镜和贴纸。
- `FilterPipeline` 不知道相机和贴纸。
- `StickerGenerator` 不知道相机和 UI，只接受图片、返回贴纸。
- `EditorViewModel` 是唯一组合滤镜、贴纸、图层的地方。

### 4.2 模块职责

| 模块 | 职责 | 依赖 |
|---|---|---|
| `App` | 入口、根视图、依赖装配 | 全部 |
| `Camera` | 权限、会话、帧输出、拍照、设备切换 | AVFoundation |
| `Filter` | 胶片预设、LUT 加载、强度混合 | Core Image |
| `Preview` | 实时帧渲染、aspect-fill、方向处理 | MetalKit |
| `Sticker` | 动漫化推理、主体抠图、描边、贴纸模型 | Core ML, Vision |
| `Editor` | 图层模型、手势变换、合成导出 | Core Image |
| `Photo` | 拍照协调、全分辨率处理、相册写入 | AVFoundation, Photos |
| `UI` | 界面组件，无业务逻辑 | SwiftUI |
| `Core` | 日志、触觉、主题常量 | 无 |

### 4.3 目录结构

```
FilterCam/
├── project.yml
├── FilterCam/
│   ├── App/
│   │   ├── FilterCamApp.swift
│   │   ├── RootView.swift
│   │   └── AppEnvironment.swift
│   ├── Camera/
│   │   ├── CameraService.swift
│   │   ├── CameraServicing.swift
│   │   ├── CameraSession.swift
│   │   ├── CameraPermission.swift
│   │   └── CameraError.swift
│   ├── Filter/
│   │   ├── FilterPipeline.swift
│   │   ├── CoreImagePipeline.swift
│   │   ├── FilterPreset.swift
│   │   ├── FilmSimulation.swift
│   │   ├── LUTLoader.swift
│   │   └── PresetCatalog.swift
│   ├── Preview/
│   │   ├── CameraPreviewView.swift
│   │   └── PreviewRenderer.swift
│   ├── Sticker/
│   │   ├── StickerGenerator.swift
│   │   ├── StickerGenerating.swift
│   │   ├── AnimeStylizer.swift
│   │   ├── SubjectExtractor.swift
│   │   ├── StickerOutliner.swift
│   │   ├── FaceExaggerator.swift
│   │   └── StickerError.swift
│   ├── Editor/
│   │   ├── StickerLayer.swift
│   │   ├── EditorCanvas.swift
│   │   ├── CompositionRenderer.swift
│   │   └── ExportService.swift
│   ├── Photo/
│   │   ├── PhotoCaptureCoordinator.swift
│   │   ├── PhotoSaver.swift
│   │   └── PhotoLibraryPermission.swift
│   ├── UI/
│   │   ├── CameraScreen.swift
│   │   ├── CameraViewModel.swift
│   │   ├── EditorScreen.swift
│   │   ├── EditorViewModel.swift
│   │   ├── TopBar.swift
│   │   ├── FilterStrip.swift
│   │   ├── ShutterButton.swift
│   │   ├── IntensitySlider.swift
│   │   ├── StickerToolbar.swift
│   │   ├── PermissionGateView.swift
│   │   └── ToastView.swift
│   ├── Core/
│   │   ├── Logger.swift
│   │   ├── Haptics.swift
│   │   └── Theme.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── LUTs/            # 42 张 32³ LUT PNG，命名见第 8 节
│   │   ├── Models/
│   │   │   └── AnimeStylizer.mlpackage
│   │   └── Info.plist
│   └── FilterCam.entitlements
├── FilterCamTests/
│   ├── FilterPipelineTests.swift
│   ├── LUTLoaderTests.swift
│   ├── PresetCatalogTests.swift
│   ├── StickerGeneratorTests.swift
│   ├── CompositionTests.swift
│   └── RendererGeometryTests.swift
├── tools/
│   ├── convert_model.py
│   └── generate_luts.py
└── .github/workflows/build.yml
```

## 5. 核心接口

### 5.1 滤镜管线

```swift
protocol FilterPipeline {
    /// intensity 为 0...1；0 时输出与输入视觉一致，1 时为预设满强度。
    func process(
        _ image: CIImage,
        preset: FilterPreset,
        intensity: Float,
        adjustments: FilterAdjustments
    ) -> CIImage
}

extension FilterPipeline {
    func process(_ image: CIImage, preset: FilterPreset, intensity: Float) -> CIImage {
        process(image, preset: preset, intensity: intensity, adjustments: .neutral)
    }
}

struct FilterAdjustments: Equatable {
    var exposure: Float = 0     // -1...1，映射为 ±0.25 EV
    var contrast: Float = 0     // -1...1，映射为 0.5...1.5 倍
    var temperature: Float = 0  // -1...1，映射为 3500...9500K
    var grain: Float = 0        // -1...1，叠加到预设颗粒上

    static let neutral = FilterAdjustments()
    var isNeutral: Bool { self == .neutral }
}

struct FilterPreset: Identifiable, Equatable {
    let id: String
    let displayName: String
    let lutName: String?        // nil 表示原图；暗部偏色已烘进 LUT
    let grain: Float            // 0...1
    let vignette: Float         // 0...1
}

protocol LUTLoading {
    func load(named name: String) throws -> LUTData
}

struct LUTData {
    let dimension: Int
    let data: Data   // Float32 RGBA，索引顺序 r 最快、b 最慢（r + g*N + b*N²）
}
```

`LUTLoader` 读取 32³ 的 PNG 立方体图，转成 Float32 数据并缓存，使用 `CIColorCubeWithColorSpace` 应用到 sRGB 工作空间。

### 5.2 贴纸生成

```swift
protocol StickerGenerating {
    /// 生成贴纸。返回带透明通道、已描边的 CGImage。
    func generateSticker(from image: CGImage, options: StickerOptions) async throws -> StickerAsset
}

struct StickerOptions {
    var exaggerateFace: Bool   // 轻度大头大眼，默认 true
    var outlineWidth: CGFloat  // 白边宽度，默认 6pt
}

struct StickerAsset {
    let image: CGImage
    let suggestedSize: CGSize  // 相对原图的比例建议
}
```

生成管线：

1. **动漫化**：`AnimeStylizer` 用 Core ML 模型对整图推理，输出风格化图。
2. **抠主体**：`SubjectExtractor` 用 `VNGenerateForegroundInstanceMaskRequest` 得到主体蒙版，缩放到风格化图尺寸。
3. **轻度夸张**（可选）：`FaceExaggerator` 用 `VNDetectFaceLandmarksRequest` 定位人脸，围绕头部中心做 1.1x 放大、围绕双眼做 1.15x 局部放大；未检测到人脸则跳过。
4. **描边**：`StickerOutliner` 对蒙版做膨胀，生成白色轮廓，与原图合成，输出透明底贴纸。

失败降级：模型推理失败时退回"原图 + 抠图 + 白边"；抠图失败时退回"整图方形贴纸"。

### 5.3 编辑器模型

```swift
struct StickerLayer: Identifiable {
    let id: UUID
    var image: CGImage
    var center: CGPoint      // 归一化坐标 0...1，相对于画布
    var scale: CGFloat       // 1.0 = 建议尺寸
    var rotation: CGFloat    // 弧度
    var zIndex: Int
}
```

图层相等性按 `id` 判断，不比较图像数据。

画布坐标系归一化，导出时按目标分辨率还原，保证预览与导出一致。

### 5.4 状态机

相机状态：

```
initializing → requestingPermission → permissionDenied
                                   → permissionRestricted
                                   → running ⇄ paused
                                   → failed(CameraError)
```

编辑状态：

```
capturing → editing ⇄ generatingSticker → exporting → done
                              ↘ stickerFailed(可重试)
```

## 6. 数据流

### 6.1 实时预览

1. `AVCaptureVideoDataOutput` 输出 BGRA 1920×1080 30fps。
2. 转 `CIImage`，应用方向变换。
3. `FilterPipeline.process` 应用当前胶片预设与强度。
4. `PreviewRenderer` 计算 aspect-fill，用共享 `CIContext` 渲染到 `MTKView`。
5. 渲染在专用串行队列，丢帧策略为只保留最新帧。

### 6.2 拍照与编辑

1. 快门 → `AVCapturePhotoOutput.capturePhoto`。
2. 全分辨率 `Data` → `CIImage`，应用方向变换。
3. 用同一条 `FilterPipeline` 处理全分辨率图，得到成片。
4. 进入编辑页，成片作为画布底图。
5. 用户点"生成贴纸"→ `StickerGenerator` 处理**成片**（不是原图），返回贴纸。
6. 贴纸以建议尺寸出现在右下角，可拖动/缩放/旋转/删除。
7. 点"保存"→ `CompositionRenderer` 按原分辨率合成底图与所有贴纸 → `PHPhotoLibrary` 写入相册相簿 `FilterCam`。

补充约定：

- 编辑页可以直接点"保存"，跳过贴纸生成。
- v1 不支持在编辑页更换滤镜，滤镜在拍照时固定。
- 同一张照片可以多次生成贴纸，生成结果各自独立成层。

### 6.3 合成与导出

- 画布尺寸 = 成片像素尺寸。
- 每个贴纸按归一化中心、缩放、旋转绘制到 `CIImage` 上，按 `zIndex` 排序。
- 使用 `CIContext.createCGImage` 输出，色彩空间固定 sRGB，避免偏色。
- 导出前检查磁盘空间，失败保留中间文件供重试。

### 6.4 强度混合

`CIDissolveTransition`，`inputTime = intensity`，输入为原图与满强度滤镜图。0% 严格等于原图，100% 等于满强度。

## 7. 界面设计

### 7.1 相机页

```
┌──────────────────────────┐
│  ⚡ 闪光灯          🔄 镜头 │
│                          │
│        实时取景           │
│      （胶片滤镜）          │
│                          │
│  ──────●──────  强度 70%  │
│  ○  ○  ●  ○  ○  [全部]   │
│  [相册]    ◉    [前后]     │
└──────────────────────────┘
```

| 组件 | 行为 |
|---|---|
| 顶部左 | 闪光灯循环：自动 → 开 → 关 |
| 顶部右 | 切换前后摄像头 |
| 取景器 | 全屏 aspect-fill，套用当前滤镜 |
| 强度滑杆 | 选中非"原图"时出现，0–100% |
| 滤镜横条 | 显示"最近使用"6 个 + 收藏项，末尾"全部"按钮 |
| 全部按钮 | 打开滤镜库（全屏、分类页签、网格缩略图、收藏） |
| 快门 | 白色圆形，触觉反馈 + 闪屏动画 |
| 左下角 | 最近一张缩略图，点击查看 |

滤镜库界面：

```
┌──────────────────────────┐
│  ✕ 滤镜库                  │
│ [胶片模拟][经典胶片][电影][季节][实验] │
│                          │
│  ▣  ▣  ▣  ▣               │
│  标准 鲜艳 柔彩 经典         │
│  ▣  ▣  ▣  ▣               │
│  ...                     │
└──────────────────────────┘
```

- 每个格子显示该滤镜对当前画面的实时缩略图 + 名称，长按收藏。
- 选中即应用到取景器并返回相机页。
- 收藏与最近使用存 `@AppStorage`，最多各 12 个。
- 43 个缩略图不一次性生成：先显示占位，后台队列逐个填充。

### 7.2 编辑页

```
┌──────────────────────────┐
│  ← 返回        保存        │
│                          │
│        成片画布           │
│      （可放贴纸）          │
│                          │
│  [生成贴纸]  [撤销]  [删除] │
└──────────────────────────┘
```

| 组件 | 行为 |
|---|---|
| 生成贴纸 | 触发端侧生成，期间显示进度与可取消 |
| 贴纸手势 | 单指拖动、双指缩放旋转、点选显示删除按钮 |
| 撤销 | 撤销最近一次贴纸操作，v1 保留 20 步 |
| 保存 | 合成导出到相册，成功后提示并可查看 |

视觉规范：背景纯黑，控件半透明白，圆角 8pt，系统字体。所有点击区域不小于 44×44pt。

## 8. 滤镜预设库

v1 内置 **42 款滤镜 + 原图，共 43 个选项**，分 5 类。全部由 `tools/generate_luts.py` 按色彩科学参数生成 32³ LUT，不搬运第三方 LUT，版权干净、可商用。

命名使用描述性中文名，不使用第三方商标（如 Portra、Classic Chrome），避免上架争议；id 为内部稳定标识，不随显示名变化。

### 8.1 胶片模拟（10）

| id | 名称 | 观感 |
|---|---|---|
| `sim_standard` | 标准正片 | 中性、自然、微饱和 |
| `sim_vivid` | 鲜艳正片 | 高饱和、高对比、风光感 |
| `sim_soft` | 柔彩正片 | 低对比、肤色柔和 |
| `sim_chrome` | 经典正片 | 低饱和、暗部偏青、纪实感 |
| `sim_negative` | 经典负片 | 高对比、偏洋红、怀旧 |
| `sim_nostalgic` | 怀旧负片 | 暖调、高光偏黄、年代感 |
| `sim_cinema` | 电影负片 | 低饱和、宽容度高、灰调 |
| `sim_bleach` | 漂白负片 | 高对比、低饱和、硬朗 |
| `sim_mono` | 细腻黑白 | 中灰丰富、层次细腻 |
| `sim_mono_red` | 黑白红调 | 黑白 + 红滤镜，压暗蓝天 |

### 8.2 经典胶片（10）

| id | 名称 | 观感 |
|---|---|---|
| `warm_portrait` | 暖调人像 | 肤色偏暖、高光奶油感 |
| `cool_portrait` | 冷调人像 | 肤色偏冷、干净通透 |
| `golden_day` | 金色日光 | 金黄高光、怀旧日常 |
| `vivid_landscape` | 鲜锐风景 | 高饱和、高清晰、蓝绿突出 |
| `daily_street` | 日常街拍 | 中性偏冷、轻微颗粒 |
| `coarse_mono` | 粗颗粒黑白 | 强颗粒、深黑、粗粝 |
| `high_contrast_mono` | 高反差黑白 | 极强对比、硬光感 |
| `tungsten_night` | 夜景钨丝 | 钨丝灯暖调、暗部偏蓝 |
| `instant` | 拍立得 | 低对比、偏青、褪色 |
| `retro_red` | 复古红调 | 红棕偏色、低饱和 |

### 8.3 电影感（8）

| id | 名称 | 观感 |
|---|---|---|
| `teal_orange` | 青橙电影 | 暗部青、肤色橙，商业片感 |
| `bleach_bypass` | 漂白 | 去饱和 + 高对比 |
| `cross_process` | 交叉冲洗 | 暗部青绿、高光偏黄 |
| `faded_matte` | 褪色哑光 | 黑位抬升、低对比、哑光 |
| `warm_cinema` | 暖调电影 | 琥珀色、柔和滚降 |
| `cool_noir` | 冷调黑色 | 蓝灰、硬阴影、悬疑感 |
| `neon_night` | 霓虹夜景 | 品红与青、高光溢出 |
| `desert` | 沙丘暖沙 | 土黄、低饱和、干燥感 |

### 8.4 季节与情绪（8）

| id | 名称 | 观感 |
|---|---|---|
| `spring` | 春日 | 粉绿、明亮、低对比 |
| `summer` | 盛夏 | 高饱和、强光、暖 |
| `autumn` | 秋日 | 橙红、暖调、浓郁 |
| `winter` | 冬日 | 冷蓝、低饱和、清冽 |
| `rainy` | 雨天 | 灰蓝、低对比、湿润 |
| `sunset` | 黄昏 | 金橙、紫红、高光柔 |
| `dawn` | 清晨 | 淡蓝、薄雾、低对比 |
| `forest` | 森林 | 深绿、暗调、自然 |

### 8.5 复古与实验（6）

| id | 名称 | 观感 |
|---|---|---|
| `sepia` | 棕褐 | 单色棕褐、老照片 |
| `cyanotype` | 蓝晒 | 单色普鲁士蓝 |
| `infrared` | 红外 | 植被发白、天空深、超现实 |
| `lomo` | LOMO | 高饱和、强暗角、偏色 |
| `duotone_purple` | 紫调双色 | 暗部紫、高光青 |
| `negative` | 负片反转 | 颜色反转、实验感 |

### 8.6 实现说明

- 每款一张 32³ LUT PNG（1024×32），约 200–400KB，42 张合计约 10–15MB。
- `CIColorCubeWithColorSpace` 应用，工作色彩空间固定 sRGB。
- 颗粒、暗角、强度混合在 LUT 之外叠加，参数存在预设里。
- 生成脚本参数化：每款滤镜 = 一组曲线/色相/分离色调参数，改参数即改风格。
- 后续拿到正版 LUT，可直接替换 PNG，不改代码。
- 滤镜切换只换 `CIColorCube`，不影响帧率。

### 8.7 滤镜参数微调

在强度之外，提供四根滑杆，作用在 LUT 之后（相当于对扫描件做后期）：

| 参数 | 范围 | 映射 |
|---|---|---|
| 曝光 | -1...1 | `CIExposureAdjust`，EV = 参数 × 0.25 |
| 对比度 | -1...1 | `CIColorControls.contrast` = 1 + 参数 × 0.5 |
| 色温 | -1...1 | `CITemperatureAndTint`，目标色温 6500 + 参数 × 3000 |
| 颗粒 | -1...1 | 最终颗粒 = clamp(预设颗粒 + 参数 × 0.3, 0...1) |

规则：

- 参数为中性时不插入任何额外滤镜，保证与原预设输出一致。
- 每款预设记住自己的微调值，切换滤镜时恢复。
- 编辑页提供"重置"，一键回到中性。
- 预览与导出使用同一套参数，避免所见非所得。

## 9. Q 版贴纸生成

| 步骤 | 实现 | 失败降级 |
|---|---|---|
| 动漫化 | Core ML 风格化模型，输入长边 1024 | 跳过，用原图 |
| 抠主体 | Vision 前景实例蒙版 | 整图方形贴纸 |
| 轻度夸张 | Vision 人脸关键点 + 局部变形 | 跳过 |
| 白描边 | 蒙版膨胀 + 白色合成 | 无描边 |

模型：

- 选**可商用**（Apache-2.0 或 MIT）的轻量卡通化模型，随包分发。
- 通过 `tools/convert_model.py` 在 CI 的 macOS 机器上转换为 `.mlpackage`，产物提交入库。
- 模型许可证与来源记录在 `docs/superpowers/specs/model-license.md`，上架前复核。
- 目标：iPhone 12 及以上，1024 长边推理 < 1.5 秒。

### 9.5 胶片边框

三种边框，导出时合成到成片外围：

| id | 名称 | 结构 |
|---|---|---|
| `none` | 无边框 | 原始画面 |
| `film135` | 135 齿孔 | 上下黑边 + 等距齿孔 + 底部胶片标识文字 |
| `polaroid` | 拍立得 | 四周白边，底部留宽边 |
| `wide` | 宽幅留白 | 上下白边，画面居中 |

实现：

- `FrameStyle` 枚举 + `FrameRenderer`，用 Core Graphics 程序化绘制，不依赖大图资源。
- 输出画布尺寸 = 原图 + 边框，长边不超过 4096。
- 边框颜色、齿孔间距、留白比例参数化，便于后续加新样式。
- 边框在编辑页选择，实时预览缩略图，导出时按原分辨率合成。

### 9.6 内置贴纸库

- 随包 2 个贴纸包、共 12 张，主题为「动物」「街景杂物」。
- 资源为透明 PNG，白边已烘焙；清单文件 `StickerPacks.json` 描述包名、分类、资源名。
- 用途一：取景器四周装饰（可在设置中关闭）。
- 用途二：编辑页贴纸面板，点击添加到成片，复用同一套手势。
- 素材来源：自行绘制或 CC0，记录在 `docs/superpowers/specs/sticker-license.md`，不使用来源不明素材。

## 10. 异常与边界

| 场景 | 处理 |
|---|---|
| 相机权限未决定 | 说明页，点击请求 |
| 相机权限被拒 | 全屏引导 + "去设置"，回前台重查 |
| 相机权限受限 | 提示无法使用相机 |
| 相册权限被拒 | 先存临时文件，提示可通过分享导出 |
| 来电/后台/锁屏 | 停止采集，回前台恢复 |
| 无相机/被占用 | 错误页 + 重试 |
| 贴纸生成失败 | 保留原图，提示重试或跳过 |
| 抠图无主体 | 生成整图方形贴纸并提示 |
| 导出失败 | 保留中间文件，提示重试 |
| 低内存 | 释放缩略图缓存与 LUT 缓存，重新加载 |
| 前置摄像头 | 预览镜像，成片不镜像 |
| 设备旋转 | v1 锁定竖屏 |

## 11. 权限与合规

`Info.plist`：

- `NSCameraUsageDescription`：用于拍摄带胶片滤镜的照片。
- `NSPhotoLibraryAddUsageDescription`：用于将成片和贴纸保存到相册。

合规要点：

- 所有 AI 处理在本机完成，照片不上传，v1 无网络请求。
- 贴纸生成属于端侧图像处理，不产生生成式内容，但仍需在隐私说明中写明"照片仅在本机处理"。
- 上架前需补充隐私政策页面与 App 隐私标签。
- 应用显示名 `FilterCam`；Bundle ID `com.filtercam.app`（Sideloadly 签名时可改写）。

## 12. 测试策略

### 单元测试（CI 模拟器运行）

- LUT 加载：42 张 LUT 均可加载，维度 32，输出色彩范围合法。
- 滤镜：固定输入图输出稳定；强度 0 = 原图，强度 1 = 满强度。
- 预设注册表：43 个条目、id 唯一、名称非空、LUT 资源存在。
- 滤镜分类：5 个分类均有条目，分类内顺序稳定。
- 收藏与最近使用：上限 12，去重，重启后保持。
- 贴纸：给定固定输入图，蒙版与描边输出尺寸正确；抠图失败时走降级路径。
- 合成：贴纸归一化坐标在 0.5x/1x/2x 分辨率下位置一致。
- 渲染几何：不同画面比例下的 aspect-fill 计算。

### 真机手动清单

- 权限三态流程。
- 42 款滤镜逐一实时切换，帧率无明显下降；滤镜库滚动流畅。
- 强度 0/50/100 效果符合预期。
- 收藏、最近使用、重启后保持。
- 拍照 → 编辑页 → 生成贴纸 → 拖动/缩放/旋转/删除 → 保存。
- 贴纸边缘干净、白边均匀、无黑边。
- 前置/后置、弱光、连续拍 20 张。
- 后台/来电恢复。

### 性能验收

- 预览 ≥ 30fps（iPhone 12 及以上）。
- 贴纸生成 < 2 秒（含模型推理）。
- 导出 12MP 成片 < 3 秒。
- 连续 10 次生成贴纸，内存无持续增长。

## 13. 构建与分发

### 13.1 CI 流程

`.github/workflows/build.yml`：

1. `runs-on: macos-15`，选择最新稳定 Xcode。
2. `brew install xcodegen` → `xcodegen generate`。
3. `xcodebuild test` 跑单元测试（含 Core ML 模型加载校验）。
4. `xcodebuild build`，`CODE_SIGNING_ALLOWED=NO`，产出 Release `.app`。
5. 打包 `Payload/FilterCam.app` → `FilterCam.ipa`。
6. 上传 artifact，保留 14 天。

### 13.2 安装流程（用户侧）

1. Windows 安装 Apple Devices（或 iTunes）与 Sideloadly。
2. 数据线连接 iPhone，信任此电脑。
3. Sideloadly 拖入 IPA，填写 Apple ID，Start。
4. iPhone 设置 → 通用 → VPN 与设备管理 → 信任开发者证书。
5. 首次打开允许相机与相册权限。

限制：免费 Apple ID 签名 7 天过期，到期重装；最多 3 个自签 App。付费开发者账号（¥688/年）可一年有效，并支持 TestFlight 与 App Store 上架。

### 13.3 迭代循环

改代码 → push → CI 构建（5–8 分钟）→ 下载 IPA → Sideloadly 安装（约 2 分钟）→ 真机试用 → 反馈。单轮约 15 分钟。

## 14. 里程碑

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| M1 | 工程骨架、XcodeGen、CI、权限文案 | 手机装出可运行 App，CI 出 IPA |
| M2 | 权限流程、会话、实时预览、前后切换 | 真机看到画面，切换正常 |
| M3 | LUT 滤镜管线、42 款滤镜、强度、参数微调、滤镜库与缩略图 | 实时切换流畅，色彩接近参考 |
| M4 | 贴纸生成：模型接入、抠图、描边、降级 | 真机能生成边缘干净的贴纸 |
| M5 | 编辑页：图层、手势、撤销、边框、内置贴纸库、合成导出 | 贴纸可摆放、边框正确、导出成片 |
| M6 | 异常处理、性能优化、图标启动图、验收 | 真机清单全过，性能达标 |

## 15. 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| 本地无法编译，只能靠 CI | 反馈慢 | 小步提交；先写单元测试；CI 日志即时修复 |
| coremltools 转换在 Windows 不可靠 | 模型无法产出 | 在 CI macOS 机器上转换，产物入库 |
| 动漫化模型许可证不明 | 无法上架 | 只用 Apache-2.0/MIT 模型，记录来源；上架前复核 |
| 端侧效果达不到"Q 版"预期 | 用户失望 | 已明确效果边界；提供轻度夸张；后续可升级云端 |
| LUT 色彩不够像富士 | 卖点打折 | 用脚本参数化生成 + 样片微调，不改代码 |
| 42 款滤镜调优工作量大 | 部分滤镜效果敷衍 | 分两批交付：先 12 款精调，其余按参数基线生成后再迭代 |
| 42 张 LUT 增大安装包 | 下载/安装变慢 | 32³ LUT + PNG 压缩，控制 LUT 总量在 15MB 内 |
| 贴纸抠图边缘毛糙 | 观感差 | 蒙版羽化 + 描边膨胀参数化调优 |
| 免费签名 7 天过期 | 每周重装 | 可接受；长期使用购买付费账号 |
| App Store 隐私政策要求 | 上架受阻 | 上架前补充，不影响真机使用 |

## 16. 术语

- **胶片模拟**：模拟特定胶片色彩响应的滤镜。
- **LUT**：查找表，把输入颜色映射为输出颜色，用于精确调色。
- **贴纸**：带透明通道的抠图素材，可叠放在照片上。
- **前景实例蒙版**：Vision 输出的主体像素级蒙版。
- **未签名 IPA**：未经 Apple 签名的安装包，需 Sideloadly 等工具重签。
- **aspect-fill**：保持比例填满取景框，超出部分裁剪。
