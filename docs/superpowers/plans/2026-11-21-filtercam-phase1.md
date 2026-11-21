# FilterCam 实现计划 · 阶段一（M1–M3）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出能在 iPhone 真机运行的胶片滤镜相机：相机预览 + 42 款 LUT 滤镜实时切换 + 分类滤镜库。

**Architecture:** SwiftUI 负责界面，AVFoundation 负责采集，Core Image 负责 LUT 与强度混合，MTKView 负责预览渲染。工程用 XcodeGen 从 `project.yml` 生成，构建与测试全部在 GitHub Actions 的 macOS 机器上完成。

**Tech Stack:** Swift 5.9、iOS 17、SwiftUI、AVFoundation、Core Image、MetalKit、XcodeGen、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-11-21-ios-filter-camera-design.md`

## Global Constraints

- 最低系统版本 iOS 17.0，Swift 5.9。
- 无第三方运行时依赖；不发起任何网络请求。
- 竖屏锁定，`TARGETED_DEVICE_FAMILY = 1`（仅 iPhone）。
- 所有面向用户的文案使用中文。
- 滤镜共 42 款 + 原图 = 43 个选项，分 5 类。
- LUT 为 32³、1024×32 的 PNG，使用 sRGB 工作色彩空间。
- 滤镜 id 稳定且不含第三方商标。
- 本地（Windows）无法编译，所有验证通过 `git push` 触发 CI 完成。
- 每次提交前确认 `git status` 无多余文件。
- 阶段一不实现：照片保存、贴纸生成、编辑器、视频、美颜。

## 文件结构（阶段一）

```
FilterCam/
├── project.yml
├── .gitignore
├── FilterCam/
│   ├── App/FilterCamApp.swift, RootView.swift
│   ├── Camera/CameraPermission.swift, CameraError.swift,
│   │           CameraServicing.swift, CameraService.swift
│   ├── Filter/FilterPreset.swift, PresetCatalog.swift,
│   │           LUTLoader.swift, CoreImagePipeline.swift
│   ├── Preview/PreviewRenderer.swift, CameraPreviewView.swift,
│   │           AspectFill.swift
│   ├── UI/CameraViewModel.swift, CameraScreen.swift, TopBar.swift,
│   │      PermissionGateView.swift, FilterStrip.swift,
│   │      FilterLibraryView.swift, IntensitySlider.swift,
│   │      FilterStore.swift, ThumbnailService.swift
│   ├── Core/Theme.swift, Logger.swift, Haptics.swift
│   └── Resources/Assets.xcassets, LUTs/*.png
├── FilterCamTests/
│   ├── AspectFillTests.swift
│   ├── CameraPermissionTests.swift
│   ├── PresetCatalogTests.swift
│   ├── LUTLoaderTests.swift
│   ├── FilterPipelineTests.swift
│   └── FilterStoreTests.swift
├── tools/generate_luts.py
└── .github/workflows/build.yml
```

---

### Task 0: 远程仓库与凭证（用户操作）

**Files:**
- Modify: 无（本机 git 配置）

**Interfaces:**
- Produces: `origin` 远程地址；后续所有 `git push` 依赖它。

- [ ] **Step 1: 在 GitHub 创建空仓库**

用户操作：创建名为 `FilterCam` 的空仓库，不要初始化 README。

- [ ] **Step 2: 登录 GitHub CLI**

Run: `gh auth login`
Expected: 选择 GitHub.com → HTTPS → 浏览器授权成功。

- [ ] **Step 3: 配置远程并推送**

```bash
git remote add origin https://github.com/<你的用户名>/FilterCam.git
git push -u origin main
```

Expected: 代码出现在 GitHub 仓库，Actions 开始第一次构建。

---

### Task 1: 工程骨架与可运行 App

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `FilterCam/App/FilterCamApp.swift`
- Create: `FilterCam/App/RootView.swift`
- Create: `FilterCam/Core/Theme.swift`
- Create: `FilterCam/Core/Logger.swift`
- Create: `FilterCam/Core/Haptics.swift`
- Create: `FilterCam/Resources/Assets.xcassets/Contents.json`
- Create: `FilterCam/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `FilterCam/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `FilterCamTests/SmokeTests.swift`

**Interfaces:**
- Produces: `FilterCamApp`（App 入口）、`RootView`（根视图）、`Theme`、`Log`、`Haptics`。
- 后续任务会修改 `RootView.body`，把占位文字换成 `CameraScreen()`。

- [ ] **Step 1: 写 `project.yml`**

```yaml
name: FilterCam
options:
  bundleIdPrefix: com.filtercam
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
targets:
  FilterCam:
    type: application
    platform: iOS
    sources:
      - path: FilterCam
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.filtercam.app
        PRODUCT_NAME: FilterCam
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        GENERATE_INFOPLIST_FILE: NO
    info:
      path: FilterCam/Resources/Info.plist
      properties:
        CFBundleDisplayName: FilterCam
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UIRequiresFullScreen: true
        NSCameraUsageDescription: 用于拍摄带胶片滤镜的照片。
        NSPhotoLibraryAddUsageDescription: 用于将成片保存到相册。
  FilterCamTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: FilterCamTests
    dependencies:
      - target: FilterCam
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.filtercam.app.tests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/FilterCam.app/FilterCam"
        BUNDLE_LOADER: "$(TEST_HOST)"
schemes:
  FilterCam:
    build:
      targets:
        FilterCam: all
        FilterCamTests: [test]
    test:
      targets:
        - FilterCamTests
```

- [ ] **Step 2: 写 `.gitignore`**

```gitignore
.DS_Store
build/
DerivedData/
*.xcodeproj
*.xcworkspace
xcuserdata/
FilterCam/Resources/Info.plist
```

- [ ] **Step 3: 写 App 入口与占位根视图**

`FilterCam/App/FilterCamApp.swift`：

```swift
import SwiftUI

@main
struct FilterCamApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
```

`FilterCam/App/RootView.swift`：

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("FilterCam")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.control)
        }
    }
}
```

- [ ] **Step 4: 写 Core 常量与工具**

`FilterCam/Core/Theme.swift`：

```swift
import SwiftUI

enum Theme {
    static let background = Color.black
    static let control = Color.white.opacity(0.9)
    static let controlDim = Color.white.opacity(0.55)
    static let overlay = Color.black.opacity(0.45)
    static let cornerRadius: CGFloat = 8
    static let hitTarget: CGFloat = 44
}
```

`FilterCam/Core/Logger.swift`：

```swift
import OSLog

enum Log {
    static let camera = Logger(subsystem: "com.filtercam.app", category: "camera")
    static let filter = Logger(subsystem: "com.filtercam.app", category: "filter")
    static let ui = Logger(subsystem: "com.filtercam.app", category: "ui")
}
```

`FilterCam/Core/Haptics.swift`：

```swift
import UIKit

enum Haptics {
    static func shutter() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
```

- [ ] **Step 5: 写资源目录占位文件**

`FilterCam/Resources/Assets.xcassets/Contents.json`：

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`FilterCam/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`：

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "1.000", "red" : "1.000" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`FilterCam/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`：

```json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 6: 写冒烟测试**

`FilterCamTests/SmokeTests.swift`：

```swift
import XCTest
@testable import FilterCam

final class SmokeTests: XCTestCase {
    func testThemeHitTargetIsAccessible() {
        XCTAssertGreaterThanOrEqual(Theme.hitTarget, 44)
    }
}
```

- [ ] **Step 7: 生成工程并本地检查文件**

Run: `xcodegen generate`（本地不可用则跳过，交给 CI）
Expected: 生成 `FilterCam.xcodeproj`，该目录已被 `.gitignore` 忽略。

- [ ] **Step 8: 提交**

```bash
git add project.yml .gitignore FilterCam FilterCamTests
git commit -m "feat: 工程骨架与可运行入口"
```

---

### Task 2: CI 构建流水线

**Files:**
- Create: `.github/workflows/build.yml`
- Create: `tools/ci/select-simulator.sh`
- Modify: `README.md`（新建）

**Interfaces:**
- Consumes: Task 1 的 `project.yml` 与 `FilterCam` scheme。
- Produces: GitHub Actions 产物 `FilterCam-ipa`；后续所有任务的验证都依赖它。

- [ ] **Step 1: 写模拟器选择脚本**

`tools/ci/select-simulator.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json, sys

data = json.load(sys.stdin)["devices"]
for runtime in sorted(data, reverse=True):
    for device in data[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("no iPhone simulator available")
'
```

- [ ] **Step 2: 写 CI 工作流**

`.github/workflows/build.yml`：

```yaml
name: Build

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Show Xcode version
        run: xcodebuild -version

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project
        run: xcodegen generate

      - name: Run tests
        run: |
          UDID="$(bash tools/ci/select-simulator.sh)"
          xcodebuild test \
            -project FilterCam.xcodeproj \
            -scheme FilterCam \
            -destination "platform=iOS Simulator,id=$UDID" \
            CODE_SIGNING_ALLOWED=NO

      - name: Build app
        run: |
          xcodebuild build \
            -project FilterCam.xcodeproj \
            -scheme FilterCam \
            -configuration Release \
            -sdk iphoneos \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY=""

      - name: Package unsigned IPA
        run: |
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/FilterCam.app Payload/
          zip -r FilterCam.ipa Payload

      - name: Upload IPA
        uses: actions/upload-artifact@v4
        with:
          name: FilterCam-ipa
          path: FilterCam.ipa
          retention-days: 14
```

- [ ] **Step 3: 写 README**

`README.md`：

```markdown
# FilterCam

iOS 胶片滤镜相机。实时预览 42 款 LUT 滤镜，拍照后可生成 Q 版漫画贴纸。

## 构建

本仓库没有本地 Mac 开发环境，所有构建与测试在 GitHub Actions 完成。

1. 推送代码到 `main`。
2. 打开 Actions → Build → 下载 `FilterCam-ipa` 产物。
3. Windows 上用 Sideloadly 配合 Apple ID 安装到 iPhone。

## 文档

- 设计文档：`docs/superpowers/specs/2026-11-21-ios-filter-camera-design.md`
- 实现计划：`docs/superpowers/plans/2026-11-21-filtercam-phase1.md`
```

- [ ] **Step 4: 提交并推送**

```bash
git add .github tools README.md
git commit -m "ci: GitHub Actions 构建、测试与 IPA 打包"
git push origin main
```

- [ ] **Step 5: 在 Actions 页面确认绿灯**

Expected: `Build` 工作流成功，产物中出现 `FilterCam-ipa`。
若失败，读取日志修复后再次推送，直到绿灯。

---

### Task 3: 相机权限模型

**Files:**
- Create: `FilterCam/Camera/CameraPermission.swift`
- Create: `FilterCamTests/CameraPermissionTests.swift`

**Interfaces:**
- Produces:
  - `enum CameraAuthorization { case notDetermined, authorized, denied, restricted }`
  - `protocol CameraPermissionProviding { var status: CameraAuthorization { get }; func request() async -> CameraAuthorization }`
  - `struct SystemCameraPermission: CameraPermissionProviding`
  - `CameraAuthorization.map(_:)` 用于把系统状态映射为领域状态，便于测试。

- [ ] **Step 1: 写失败测试**

`FilterCamTests/CameraPermissionTests.swift`：

```swift
import AVFoundation
import XCTest
@testable import FilterCam

final class CameraPermissionTests: XCTestCase {
    func testMapsNotDetermined() {
        XCTAssertEqual(CameraAuthorization.map(.notDetermined), .notDetermined)
    }

    func testMapsAuthorized() {
        XCTAssertEqual(CameraAuthorization.map(.authorized), .authorized)
    }

    func testMapsDenied() {
        XCTAssertEqual(CameraAuthorization.map(.denied), .denied)
    }

    func testMapsRestricted() {
        XCTAssertEqual(CameraAuthorization.map(.restricted), .restricted)
    }
}
```

- [ ] **Step 2: 推送确认测试失败**

Run: `git push origin main`
Expected: CI 失败，报错 `cannot find 'CameraAuthorization' in scope`。

- [ ] **Step 3: 写实现**

`FilterCam/Camera/CameraPermission.swift`：

```swift
import AVFoundation

enum CameraAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

protocol CameraPermissionProviding {
    var status: CameraAuthorization { get }
    func request() async -> CameraAuthorization
}

struct SystemCameraPermission: CameraPermissionProviding {
    var status: CameraAuthorization {
        CameraAuthorization.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func request() async -> CameraAuthorization {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : CameraAuthorization.map(AVCaptureDevice.authorizationStatus(for: .video))
    }
}
```

- [ ] **Step 4: 推送确认测试通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 5: 提交**

```bash
git add FilterCam/Camera/CameraPermission.swift FilterCamTests/CameraPermissionTests.swift
git commit -m "feat: 相机权限模型"
git push origin main
```

---

### Task 4: 相机服务与会话

**Files:**
- Create: `FilterCam/Camera/CameraError.swift`
- Create: `FilterCam/Camera/CameraServicing.swift`
- Create: `FilterCam/Camera/CameraService.swift`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum CameraError: LocalizedError, Equatable`
  - `enum CameraRuntimeState: Equatable { case idle, running, interrupted, failed(CameraError) }`
  - `enum FlashMode: String, CaseIterable, Identifiable { case auto, on, off }`
  - `protocol CameraServicing: AnyObject`，成员：
    - `var onFrame: ((CIImage) -> Void)?`
    - `var onStateChange: ((CameraRuntimeState) -> Void)?`
    - `func start() async throws`
    - `func stop()`
    - `func switchCamera() async throws`
    - `func setFlashMode(_ mode: FlashMode)`
    - `func capturePhoto() async throws -> Data`
  - `final class CameraService: NSObject, CameraServicing`

- [ ] **Step 1: 写错误与协议**

`FilterCam/Camera/CameraError.swift`：

```swift
import Foundation

enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case permissionRestricted
    case noCameraAvailable
    case configurationFailed(String)
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "相机权限被拒绝，请到设置中开启。"
        case .permissionRestricted: return "相机使用受到限制。"
        case .noCameraAvailable: return "没有可用的摄像头。"
        case .configurationFailed(let message): return "相机配置失败：\(message)"
        case .captureFailed(let message): return "拍照失败：\(message)"
        }
    }
}
```

`FilterCam/Camera/CameraServicing.swift`：

```swift
import AVFoundation
import CoreImage

enum CameraRuntimeState: Equatable {
    case idle
    case running
    case interrupted
    case failed(CameraError)
}

enum FlashMode: String, CaseIterable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .on: return "开"
        case .off: return "关"
        }
    }

    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on: return .on
        case .off: return .off
        }
    }
}

protocol CameraServicing: AnyObject {
    var onFrame: ((CIImage) -> Void)? { get set }
    var onStateChange: ((CameraRuntimeState) -> Void)? { get set }

    func start() async throws
    func stop()
    func switchCamera() async throws
    func setFlashMode(_ mode: FlashMode)
    func capturePhoto() async throws -> Data
}
```

- [ ] **Step 2: 写 `CameraService`**

`FilterCam/Camera/CameraService.swift`：

```swift
import AVFoundation
import CoreImage

final class CameraService: NSObject, CameraServicing {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.filtercam.camera.session")
    private let videoQueue = DispatchQueue(label: "com.filtercam.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var flashMode: FlashMode = .auto
    private var isConfigured = false
    private var isObserving = false
    private let photoLock = NSLock()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    var onFrame: ((CIImage) -> Void)?
    var onStateChange: ((CameraRuntimeState) -> Void)?

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    self.observeSessionIfNeeded()
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    self.onStateChange?(.running)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.onStateChange?(.idle)
        }
    }

    func switchCamera() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.switchCameraLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func setFlashMode(_ mode: FlashMode) {
        sessionQueue.async { self.flashMode = mode }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraError.captureFailed("相机会话未运行"))
                    return
                }
                self.photoLock.lock()
                let isBusy = self.photoContinuation != nil
                if !isBusy {
                    self.photoContinuation = continuation
                }
                self.photoLock.unlock()
                guard !isBusy else {
                    continuation.resume(throwing: CameraError.captureFailed("上一张照片仍在处理中"))
                    return
                }
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(self.flashMode.avMode) {
                    settings.flashMode = self.flashMode.avMode
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        guard let device = Self.device(position: position) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("无法添加相机输入")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            throw CameraError.configurationFailed("无法添加视频输出")
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed("无法添加照片输出")
        }
        session.addOutput(photoOutput)

        applyConnectionSettings(position: position)
        isConfigured = true
    }

    private func switchCameraLocked() throws {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let device = Self.device(position: newPosition) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let previousInput = videoInput
        if let previousInput {
            session.removeInput(previousInput)
        }
        guard session.canAddInput(input) else {
            if let previousInput {
                session.addInput(previousInput)
            }
            throw CameraError.configurationFailed("无法切换摄像头")
        }
        session.addInput(input)
        videoInput = input
        position = newPosition
        applyConnectionSettings(position: newPosition)
    }

    private func applyConnectionSettings(position: AVCaptureDevice.Position) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        connection.isVideoMirrored = position == .front
    }

    private func observeSessionIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onStateChange?(.interrupted)
        }
        center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onStateChange?(.running)
        }
        center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            let message = error?.localizedDescription ?? "相机运行时错误"
            self?.onStateChange?(.failed(.configurationFailed(message)))
        }
    }

    private static func device(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(CIImage(cvPixelBuffer: buffer))
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let continuation: CheckedContinuation<Data, Error>?
        photoLock.lock()
        continuation = photoContinuation
        photoContinuation = nil
        photoLock.unlock()
        if let error {
            continuation?.resume(throwing: CameraError.captureFailed(error.localizedDescription))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: CameraError.captureFailed("照片数据为空"))
            return
        }
        continuation?.resume(returning: data)
    }
}
```

- [ ] **Step 3: 推送确认编译通过**

Run: `git push origin main`
Expected: CI 绿灯（本任务没有新增单元测试，真机行为在 Task 6 验证）。

- [ ] **Step 4: 提交**

```bash
git add FilterCam/Camera
git commit -m "feat: AVFoundation 相机服务与会话"
git push origin main
```

---

### Task 5: 预览渲染与取景视图

**Files:**
- Create: `FilterCam/Preview/AspectFill.swift`
- Create: `FilterCam/Preview/PreviewRenderer.swift`
- Create: `FilterCam/Preview/CameraPreviewView.swift`
- Create: `FilterCamTests/AspectFillTests.swift`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum AspectFill { static func transform(contentSize: CGSize, in bounds: CGRect) -> CGAffineTransform }`
  - `final class PreviewRenderer: NSObject, MTKViewDelegate`，成员：`init(device:)`、`let device: MTLDevice`、`var onNeedsDisplay: (() -> Void)?`、`func submit(_ image: CIImage)`
  - `struct CameraPreviewView: UIViewRepresentable`，初始化参数 `renderer: PreviewRenderer`

- [ ] **Step 1: 写失败测试**

`FilterCamTests/AspectFillTests.swift`：

```swift
import XCTest
@testable import FilterCam

final class AspectFillTests: XCTestCase {
    func testWideContentFillsTallBounds() {
        let transform = AspectFill.transform(
            contentSize: CGSize(width: 100, height: 200),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let origin = CGPoint.zero.applying(transform)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, -150, accuracy: 0.001)
    }

    func testTallContentFillsWideBounds() {
        let transform = AspectFill.transform(
            contentSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let origin = CGPoint.zero.applying(transform)
        XCTAssertEqual(origin.x, -150, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)
    }

    func testMatchingAspectRatioHasNoOffset() {
        let transform = AspectFill.transform(
            contentSize: CGSize(width: 100, height: 100),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let origin = CGPoint.zero.applying(transform)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)
    }

    func testZeroSizeReturnsIdentity() {
        let transform = AspectFill.transform(
            contentSize: .zero,
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        XCTAssertEqual(transform, .identity)
    }
}
```

- [ ] **Step 2: 推送确认测试失败**

Run: `git push origin main`
Expected: CI 失败，报错 `cannot find 'AspectFill' in scope`。

- [ ] **Step 3: 写实现**

`FilterCam/Preview/AspectFill.swift`：

```swift
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
```

`FilterCam/Preview/PreviewRenderer.swift`：

```swift
import CoreImage
import MetalKit

final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let context: CIContext
    private let lock = NSLock()
    private var latest: CIImage?

    var onNeedsDisplay: (() -> Void)?

    init(device: MTLDevice) {
        self.device = device
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
        guard let drawable = view.currentDrawable else { return }
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
            commandBuffer: nil,
            bounds: bounds,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
    }
}
```

`FilterCam/Preview/CameraPreviewView.swift`：

```swift
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
```

- [ ] **Step 4: 推送确认测试通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 5: 提交**

```bash
git add FilterCam/Preview FilterCamTests/AspectFillTests.swift
git commit -m "feat: 预览渲染器与取景视图"
git push origin main
```

---

### Task 6: 相机页状态机与权限引导

**Files:**
- Create: `FilterCam/App/AppEnvironment.swift`
- Create: `FilterCam/UI/CameraViewModel.swift`
- Create: `FilterCam/UI/PermissionGateView.swift`
- Create: `FilterCam/UI/TopBar.swift`
- Create: `FilterCam/UI/CameraScreen.swift`
- Modify: `FilterCam/App/RootView.swift`

**Interfaces:**
- Consumes: `CameraServicing`、`CameraService`、`CameraPermissionProviding`、`SystemCameraPermission`、`PreviewRenderer`、`CameraPreviewView`、`FlashMode`、`Theme`。
- Produces:
  - `enum AppEnvironment { static func makeRenderer() -> PreviewRenderer? }`
  - `@MainActor final class CameraViewModel: ObservableObject`，成员：`state`、`flashMode`、`isFrontCamera`、`previewRenderer`、`onAppear()`、`onDisappear()`、`toggleFlash()`、`flipCamera()`、`retry()`。
  - `struct CameraScreen: View`、`struct PermissionGateView: View`、`struct TopBar: View`。

- [ ] **Step 1: 写渲染器工厂与状态机**

`FilterCam/App/AppEnvironment.swift`：

```swift
import Metal

enum AppEnvironment {
    static func makeRenderer() -> PreviewRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return PreviewRenderer(device: device)
    }
}
```

`FilterCam/UI/CameraViewModel.swift`：

```swift
import CoreImage
import SwiftUI

@MainActor
final class CameraViewModel: ObservableObject {
    enum State: Equatable {
        case initializing
        case requestingPermission
        case permissionDenied
        case permissionRestricted
        case running
        case paused
        case failed(String)
    }

    @Published private(set) var state: State = .initializing
    @Published private(set) var flashMode: FlashMode = .auto
    @Published private(set) var isFrontCamera = false

    let previewRenderer: PreviewRenderer?
    private let camera: CameraServicing
    private let permission: CameraPermissionProviding

    init(
        camera: CameraServicing = CameraService(),
        permission: CameraPermissionProviding = SystemCameraPermission(),
        previewRenderer: PreviewRenderer?
    ) {
        self.camera = camera
        self.permission = permission
        self.previewRenderer = previewRenderer
        bindCamera()
    }

    func onAppear() {
        guard previewRenderer != nil else {
            state = .failed("设备不支持 Metal 渲染")
            return
        }
        Task { await start() }
    }

    func onDisappear() {
        camera.stop()
    }

    func retry() {
        Task { await start() }
    }

    func toggleFlash() {
        let all = FlashMode.allCases
        let index = all.firstIndex(of: flashMode) ?? 0
        flashMode = all[(index + 1) % all.count]
        camera.setFlashMode(flashMode)
    }

    func flipCamera() {
        Task {
            do {
                try await camera.switchCamera()
                isFrontCamera.toggle()
            } catch {
                Log.camera.error("切换摄像头失败: \(error.localizedDescription)")
            }
        }
    }

    private func bindCamera() {
        camera.onFrame = { [weak self] image in
            self?.previewRenderer?.submit(image)
        }
        camera.onStateChange = { [weak self] runtime in
            Task { @MainActor in
                self?.apply(runtime)
            }
        }
    }

    private func apply(_ runtime: CameraRuntimeState) {
        switch runtime {
        case .idle:
            break
        case .running:
            if state != .permissionDenied && state != .permissionRestricted {
                state = .running
            }
        case .interrupted:
            state = .paused
        case .failed(let error):
            state = .failed(error.localizedDescription)
        }
    }

    private func start() async {
        switch permission.status {
        case .authorized:
            await runSession()
        case .notDetermined:
            state = .requestingPermission
            let result = await permission.request()
            switch result {
            case .authorized:
                await runSession()
            case .restricted:
                state = .permissionRestricted
            default:
                state = .permissionDenied
            }
        case .denied:
            state = .permissionDenied
        case .restricted:
            state = .permissionRestricted
        }
    }

    private func runSession() async {
        do {
            try await camera.start()
            state = .running
        } catch let error as CameraError {
            switch error {
            case .permissionDenied:
                state = .permissionDenied
            case .permissionRestricted:
                state = .permissionRestricted
            default:
                state = .failed(error.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: 写权限引导页**

`FilterCam/UI/PermissionGateView.swift`：

```swift
import SwiftUI

struct PermissionGateView: View {
    let title: String
    let message: String
    let showsSettingsButton: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.controlDim)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.control)

            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.controlDim)
                .padding(.horizontal, 32)

            if showsSettingsButton {
                Button("去设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }

            Button("重试", action: retry)
                .foregroundStyle(Theme.controlDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
```

- [ ] **Step 3: 写顶栏与相机页**

`FilterCam/UI/TopBar.swift`：

```swift
import SwiftUI

struct TopBar: View {
    let flashMode: FlashMode
    let onFlash: () -> Void
    let onFlip: () -> Void

    var body: some View {
        HStack {
            Button(action: onFlash) {
                Label(flashMode.displayName, systemImage: flashSymbol)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.control)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.hitTarget)
                    .background(Theme.overlay, in: Capsule())
            }

            Spacer()

            Button(action: onFlip) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.control)
                    .frame(width: Theme.hitTarget, height: Theme.hitTarget)
                    .background(Theme.overlay, in: Circle())
            }
        }
        .padding(.horizontal, 16)
    }

    private var flashSymbol: String {
        switch flashMode {
        case .auto: return "bolt.badge.a"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        }
    }
}
```

`FilterCam/UI/CameraScreen.swift`：

```swift
import SwiftUI

struct CameraScreen: View {
    @StateObject private var viewModel: CameraViewModel

    init() {
        _viewModel = StateObject(
            wrappedValue: CameraViewModel(previewRenderer: AppEnvironment.makeRenderer())
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let renderer = viewModel.previewRenderer {
                CameraPreviewView(renderer: renderer)
                    .ignoresSafeArea()
            }

            VStack {
                TopBar(
                    flashMode: viewModel.flashMode,
                    onFlash: viewModel.toggleFlash,
                    onFlip: viewModel.flipCamera
                )
                Spacer()
            }
            .padding(.top, 8)

            overlay
        }
        .onAppear(perform: viewModel.onAppear)
        .onDisappear(perform: viewModel.onDisappear)
    }

    @ViewBuilder
    private var overlay: some View {
        switch viewModel.state {
        case .permissionDenied:
            PermissionGateView(
                title: "需要相机权限",
                message: "FilterCam 需要访问相机才能拍摄照片。请在系统设置中允许相机访问。",
                showsSettingsButton: true,
                retry: viewModel.retry
            )
        case .permissionRestricted:
            PermissionGateView(
                title: "相机不可用",
                message: "当前设备限制了相机访问，可能由家长控制或设备管理策略导致。",
                showsSettingsButton: false,
                retry: viewModel.retry
            )
        case .failed(let message):
            PermissionGateView(
                title: "相机启动失败",
                message: message,
                showsSettingsButton: false,
                retry: viewModel.retry
            )
        case .requestingPermission:
            ProgressView("正在请求相机权限…")
                .tint(Theme.control)
                .foregroundStyle(Theme.control)
        case .paused:
            Text("相机已暂停")
                .font(.system(size: 15))
                .foregroundStyle(Theme.controlDim)
                .padding(12)
                .background(Theme.overlay, in: Capsule())
        case .initializing, .running:
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: 让根视图进入相机页**

`FilterCam/App/RootView.swift`：

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        CameraScreen()
            .background(Theme.background.ignoresSafeArea())
    }
}
```

- [ ] **Step 5: 推送确认编译通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 6: 真机验证**

用 Sideloadly 安装后确认：

1. 首次启动弹出相机权限请求。
2. 允许后看到实时画面。
3. 点右上角按钮切换前后摄像头，画面变化。
4. 点左上角按钮，闪光灯图标在自动/开/关之间循环。
5. 到设置里关闭相机权限，重启 App，出现引导页。

- [ ] **Step 7: 提交**

```bash
git add FilterCam/App FilterCam/UI
git commit -m "feat: 相机页状态机、权限引导与顶栏"
git push origin main
```

---

### Task 7: 滤镜预设与目录

**Files:**
- Create: `FilterCam/Filter/FilterPreset.swift`
- Create: `FilterCam/Filter/PresetCatalog.swift`
- Create: `FilterCamTests/PresetCatalogTests.swift`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum FilterCategory: String, CaseIterable, Identifiable`，含 `displayName`。
  - `struct FilterPreset: Identifiable, Equatable, Hashable`，字段：`id`、`displayName`、`category`、`lutName: String?`、`grain: Float`、`vignette: Float`。
  - `FilterPreset.original`
  - `enum PresetCatalog { static let all: [FilterPreset]; static let byID: [String: FilterPreset]; static func presets(in:) -> [FilterPreset] }`

- [ ] **Step 1: 写失败测试**

`FilterCamTests/PresetCatalogTests.swift`：

```swift
import XCTest
@testable import FilterCam

final class PresetCatalogTests: XCTestCase {
    func testCatalogHasFortyThreeEntries() {
        XCTAssertEqual(PresetCatalog.all.count, 43)
    }

    func testIdentifiersAreUnique() {
        let ids = PresetCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testDisplayNamesAreNotEmpty() {
        XCTAssertTrue(PresetCatalog.all.allSatisfy { !$0.displayName.isEmpty })
    }

    func testEveryPresetExceptOriginalHasLUT() {
        for preset in PresetCatalog.all where preset.id != FilterPreset.original.id {
            XCTAssertNotNil(preset.lutName, "\(preset.id) 缺少 LUT")
        }
    }

    func testEveryCategoryHasPresets() {
        for category in FilterCategory.allCases {
            XCTAssertFalse(PresetCatalog.presets(in: category).isEmpty, "\(category) 为空")
        }
    }

    func testOriginalIsFirst() {
        XCTAssertEqual(PresetCatalog.all.first, FilterPreset.original)
    }
}
```

- [ ] **Step 2: 推送确认测试失败**

Run: `git push origin main`
Expected: CI 失败，报错 `cannot find 'PresetCatalog' in scope`。

- [ ] **Step 3: 写预设模型**

`FilterCam/Filter/FilterPreset.swift`：

```swift
import Foundation

enum FilterCategory: String, CaseIterable, Identifiable {
    case simulation
    case classic
    case cinema
    case season
    case experimental

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simulation: return "胶片模拟"
        case .classic: return "经典胶片"
        case .cinema: return "电影感"
        case .season: return "季节情绪"
        case .experimental: return "复古实验"
        }
    }
}

struct FilterPreset: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
    let category: FilterCategory
    let lutName: String?
    let grain: Float
    let vignette: Float

    static let original = FilterPreset(
        id: "original",
        displayName: "原图",
        category: .simulation,
        lutName: nil,
        grain: 0,
        vignette: 0
    )
}
```

- [ ] **Step 4: 写 42 款预设目录**

`FilterCam/Filter/PresetCatalog.swift`：

```swift
import Foundation

enum PresetCatalog {
    static let all: [FilterPreset] = [FilterPreset.original] + filmPresets + classicPresets + cinemaPresets + seasonPresets + experimentalPresets

    static let byID: [String: FilterPreset] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func presets(in category: FilterCategory) -> [FilterPreset] {
        all.filter { $0.category == category }
    }

    private static func make(
        _ id: String,
        _ name: String,
        _ category: FilterCategory,
        grain: Float = 0.12,
        vignette: Float = 0.18
    ) -> FilterPreset {
        FilterPreset(
            id: id,
            displayName: name,
            category: category,
            lutName: id,
            grain: grain,
            vignette: vignette
        )
    }

    private static let filmPresets: [FilterPreset] = [
        make("sim_standard", "标准正片", .simulation, grain: 0.06, vignette: 0.08),
        make("sim_vivid", "鲜艳正片", .simulation, grain: 0.08, vignette: 0.12),
        make("sim_soft", "柔彩正片", .simulation, grain: 0.10, vignette: 0.10),
        make("sim_chrome", "经典正片", .simulation, grain: 0.14, vignette: 0.20),
        make("sim_negative", "经典负片", .simulation, grain: 0.16, vignette: 0.22),
        make("sim_nostalgic", "怀旧负片", .simulation, grain: 0.18, vignette: 0.24),
        make("sim_cinema", "电影负片", .simulation, grain: 0.12, vignette: 0.16),
        make("sim_bleach", "漂白负片", .simulation, grain: 0.20, vignette: 0.26),
        make("sim_mono", "细腻黑白", .simulation, grain: 0.08, vignette: 0.12),
        make("sim_mono_red", "黑白红调", .simulation, grain: 0.10, vignette: 0.14)
    ]

    private static let classicPresets: [FilterPreset] = [
        make("warm_portrait", "暖调人像", .classic, grain: 0.08, vignette: 0.12),
        make("cool_portrait", "冷调人像", .classic, grain: 0.08, vignette: 0.12),
        make("golden_day", "金色日光", .classic, grain: 0.14, vignette: 0.18),
        make("vivid_landscape", "鲜锐风景", .classic, grain: 0.06, vignette: 0.10),
        make("daily_street", "日常街拍", .classic, grain: 0.16, vignette: 0.18),
        make("coarse_mono", "粗颗粒黑白", .classic, grain: 0.34, vignette: 0.28),
        make("high_contrast_mono", "高反差黑白", .classic, grain: 0.18, vignette: 0.24),
        make("tungsten_night", "夜景钨丝", .classic, grain: 0.22, vignette: 0.30),
        make("instant", "拍立得", .classic, grain: 0.14, vignette: 0.22),
        make("retro_red", "复古红调", .classic, grain: 0.16, vignette: 0.22)
    ]

    private static let cinemaPresets: [FilterPreset] = [
        make("teal_orange", "青橙电影", .cinema, grain: 0.10, vignette: 0.20),
        make("bleach_bypass", "漂白", .cinema, grain: 0.14, vignette: 0.22),
        make("cross_process", "交叉冲洗", .cinema, grain: 0.18, vignette: 0.24),
        make("faded_matte", "褪色哑光", .cinema, grain: 0.12, vignette: 0.16),
        make("warm_cinema", "暖调电影", .cinema, grain: 0.10, vignette: 0.18),
        make("cool_noir", "冷调黑色", .cinema, grain: 0.12, vignette: 0.26),
        make("neon_night", "霓虹夜景", .cinema, grain: 0.16, vignette: 0.28),
        make("desert", "沙丘暖沙", .cinema, grain: 0.14, vignette: 0.20)
    ]

    private static let seasonPresets: [FilterPreset] = [
        make("spring", "春日", .season, grain: 0.08, vignette: 0.12),
        make("summer", "盛夏", .season, grain: 0.08, vignette: 0.14),
        make("autumn", "秋日", .season, grain: 0.12, vignette: 0.18),
        make("winter", "冬日", .season, grain: 0.08, vignette: 0.14),
        make("rainy", "雨天", .season, grain: 0.14, vignette: 0.18),
        make("sunset", "黄昏", .season, grain: 0.10, vignette: 0.20),
        make("dawn", "清晨", .season, grain: 0.08, vignette: 0.14),
        make("forest", "森林", .season, grain: 0.12, vignette: 0.22)
    ]

    private static let experimentalPresets: [FilterPreset] = [
        make("sepia", "棕褐", .experimental, grain: 0.18, vignette: 0.28),
        make("cyanotype", "蓝晒", .experimental, grain: 0.16, vignette: 0.26),
        make("infrared", "红外", .experimental, grain: 0.12, vignette: 0.22),
        make("lomo", "LOMO", .experimental, grain: 0.16, vignette: 0.42),
        make("duotone_purple", "紫调双色", .experimental, grain: 0.12, vignette: 0.24),
        make("negative", "负片反转", .experimental, grain: 0.14, vignette: 0.22)
    ]
}
```

- [ ] **Step 5: 推送确认测试通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 6: 提交**

```bash
git add FilterCam/Filter FilterCamTests/PresetCatalogTests.swift
git commit -m "feat: 42 款滤镜预设与分类目录"
git push origin main
```

---

### Task 8: LUT 生成脚本与 42 张资源

**Files:**
- Create: `tools/generate_luts.py`
- Create: `FilterCam/Resources/LUTs/*.png`（脚本产物，42 张）
- Create: `FilterCam/Resources/LUTs/identity.png`（测试用恒等 LUT）

**Interfaces:**
- Consumes: Task 7 的预设 id 列表。
- Produces: 与预设 id 同名的 42 张 LUT PNG + `identity.png`，均为 1024×32、sRGB、32³。

- [ ] **Step 1: 安装本地生成依赖**

Run: `python -m pip install numpy pillow`
Expected: 安装成功。

- [ ] **Step 2: 写生成脚本**

`tools/generate_luts.py`：

```python
#!/usr/bin/env python3
"""生成 32³ LUT。输出为 1024x32 的 PNG，像素顺序为 r 最慢、b 最快。"""

import os
import numpy as np
from PIL import Image

SIZE = 32
OUT_DIR = os.path.join("FilterCam", "Resources", "LUTs")

LUMA = np.array([0.2126, 0.7152, 0.0722])

FILTERS = {
    # 胶片模拟
    "sim_standard":      dict(exposure=0.05, contrast=1.02, saturation=1.04, temperature=0.02, gamma=1.0),
    "sim_vivid":         dict(exposure=0.10, contrast=1.12, saturation=1.25, temperature=0.05),
    "sim_soft":          dict(exposure=0.08, contrast=0.92, saturation=0.92, lift=0.03, gamma=1.05),
    "sim_chrome":        dict(contrast=1.08, saturation=0.72, temperature=-0.05, shadow_tint=[-0.04, 0.02, 0.05], highlight_tint=[0.02, 0.01, -0.02]),
    "sim_negative":      dict(contrast=1.18, saturation=1.05, temperature=0.08, tint=0.05, shadow_tint=[0.05, -0.02, 0.02]),
    "sim_nostalgic":     dict(contrast=1.05, saturation=0.95, temperature=0.16, lift=0.02, highlight_tint=[0.06, 0.04, -0.03]),
    "sim_cinema":        dict(contrast=1.02, saturation=0.82, temperature=-0.02, lift=0.03, shadow_tint=[-0.02, 0.03, 0.02]),
    "sim_bleach":        dict(contrast=1.35, saturation=0.45, gamma=0.95),
    "sim_mono":          dict(mono=True, contrast=1.08, gamma=1.02),
    "sim_mono_red":      dict(mono=True, mono_weights=[0.35, 0.55, 0.10], contrast=1.12),

    # 经典胶片
    "warm_portrait":     dict(exposure=0.06, contrast=0.98, saturation=1.02, temperature=0.10, highlight_tint=[0.04, 0.03, 0.0]),
    "cool_portrait":     dict(exposure=0.04, contrast=1.0, saturation=0.98, temperature=-0.08, shadow_tint=[0.0, 0.02, 0.04]),
    "golden_day":        dict(exposure=0.08, contrast=1.06, saturation=1.05, temperature=0.18, highlight_tint=[0.05, 0.03, -0.02]),
    "vivid_landscape":   dict(contrast=1.14, saturation=1.22, temperature=-0.03, gamma=0.98),
    "daily_street":      dict(contrast=1.04, saturation=0.90, temperature=-0.04, shadow_tint=[-0.02, 0.01, 0.03]),
    "coarse_mono":       dict(mono=True, contrast=1.18, lift=0.02),
    "high_contrast_mono":dict(mono=True, contrast=1.45, gamma=0.92),
    "tungsten_night":    dict(contrast=1.10, saturation=0.95, temperature=0.22, shadow_tint=[0.0, -0.02, 0.08]),
    "instant":           dict(contrast=0.88, saturation=0.80, temperature=-0.06, lift=0.06, gamma=1.08),
    "retro_red":         dict(contrast=1.05, saturation=0.78, temperature=0.12, tint=0.08),

    # 电影感
    "teal_orange":       dict(contrast=1.10, saturation=1.02, shadow_tint=[-0.06, 0.02, 0.07], highlight_tint=[0.07, 0.02, -0.05]),
    "bleach_bypass":     dict(contrast=1.30, saturation=0.55, gamma=0.98),
    "cross_process":     dict(contrast=1.16, saturation=1.10, shadow_tint=[-0.05, 0.05, 0.03], highlight_tint=[0.08, 0.03, -0.06]),
    "faded_matte":       dict(contrast=0.85, saturation=0.85, lift=0.08, gamma=1.06),
    "warm_cinema":       dict(contrast=1.04, saturation=0.95, temperature=0.14, lift=0.02),
    "cool_noir":         dict(contrast=1.22, saturation=0.72, temperature=-0.14, shadow_tint=[-0.03, 0.0, 0.06]),
    "neon_night":        dict(contrast=1.18, saturation=1.35, tint=0.06, shadow_tint=[0.06, -0.04, 0.10]),
    "desert":            dict(contrast=1.06, saturation=0.80, temperature=0.20, lift=0.03),

    # 季节情绪
    "spring":            dict(exposure=0.10, contrast=0.94, saturation=1.06, temperature=0.04, tint=0.05, lift=0.03),
    "summer":            dict(exposure=0.06, contrast=1.10, saturation=1.20, temperature=0.10),
    "autumn":            dict(contrast=1.08, saturation=1.10, temperature=0.20, tint=0.04),
    "winter":            dict(contrast=1.02, saturation=0.82, temperature=-0.18, shadow_tint=[0.0, 0.02, 0.06]),
    "rainy":             dict(contrast=0.92, saturation=0.72, temperature=-0.10, lift=0.04, gamma=1.04),
    "sunset":            dict(contrast=1.06, saturation=1.12, temperature=0.24, highlight_tint=[0.08, 0.02, -0.04]),
    "dawn":              dict(exposure=0.06, contrast=0.90, saturation=0.88, temperature=-0.06, lift=0.05, gamma=1.06),
    "forest":            dict(contrast=1.04, saturation=0.95, temperature=-0.08, tint=0.06, shadow_tint=[-0.03, 0.05, 0.0]),

    # 复古实验
    "sepia":             dict(mono=True, mono_tint=[0.12, 0.06, -0.04], contrast=1.06, gamma=1.04),
    "cyanotype":         dict(mono=True, mono_tint=[-0.08, 0.0, 0.16], contrast=1.10),
    "infrared":          dict(contrast=1.16, saturation=0.90, mono=False, shadow_tint=[0.02, 0.06, -0.02], highlight_tint=[0.10, -0.02, 0.04]),
    "lomo":              dict(contrast=1.28, saturation=1.35, temperature=0.05, tint=0.04),
    "duotone_purple":    dict(mono=True, mono_tint=[0.08, -0.04, 0.14], contrast=1.08),
    "negative":          dict(invert=True, contrast=1.04),
}


def apply_params(rgb: np.ndarray, p: dict) -> np.ndarray:
    x = rgb.astype(np.float64).copy()

    if p.get("invert"):
        x = 1.0 - x

    x *= 2.0 ** p.get("exposure", 0.0)
    x = (x - 0.5) * p.get("contrast", 1.0) + 0.5

    sat = p.get("saturation", 1.0)
    luma = x @ LUMA
    x = luma[:, None] + (x - luma[:, None]) * sat

    temp = p.get("temperature", 0.0)
    if temp:
        x[:, 0] *= 1.0 + 0.25 * temp
        x[:, 2] *= 1.0 - 0.25 * temp

    tint = p.get("tint", 0.0)
    if tint:
        x[:, 1] *= 1.0 + 0.20 * tint

    luma2 = np.clip(x @ LUMA, 0.0, 1.0)[:, None]
    shadow_w = np.clip(1.0 - luma2 * 2.0, 0.0, 1.0)
    highlight_w = np.clip(luma2 * 2.0 - 1.0, 0.0, 1.0)
    x += np.array(p.get("shadow_tint", [0, 0, 0])) * shadow_w * 0.15
    x += np.array(p.get("highlight_tint", [0, 0, 0])) * highlight_w * 0.15

    x = np.clip(x, 0.0, 1.0)
    x = x * p.get("gain", 1.0) + p.get("lift", 0.0)
    x = np.clip(x, 0.0, 1.0) ** (1.0 / p.get("gamma", 1.0))

    if p.get("mono"):
        weights = np.array(p.get("mono_weights", [0.2126, 0.7152, 0.0722]))
        luma3 = x @ weights
        x = luma3[:, None] + np.array(p.get("mono_tint", [0, 0, 0]))

    return np.clip(x, 0.0, 1.0)


def build_cube(params: dict) -> np.ndarray:
    steps = np.linspace(0.0, 1.0, SIZE)
    r = np.repeat(steps, SIZE * SIZE)
    g = np.tile(np.repeat(steps, SIZE), SIZE)
    b = np.tile(steps, SIZE * SIZE)
    rgb = np.stack([r, g, b], axis=1)
    return apply_params(rgb, params)


def save_cube(values: np.ndarray, path: str) -> None:
    rgba = np.ones((SIZE * SIZE * SIZE, 4), dtype=np.uint8) * 255
    rgba[:, :3] = np.round(values * 255.0).astype(np.uint8)
    image = Image.fromarray(rgba.reshape(SIZE, SIZE * SIZE, 4), mode="RGBA")
    image.save(path)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    save_cube(build_cube({}), os.path.join(OUT_DIR, "identity.png"))
    for name, params in FILTERS.items():
        save_cube(build_cube(params), os.path.join(OUT_DIR, f"{name}.png"))
    print(f"generated {len(FILTERS) + 1} LUTs in {OUT_DIR}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: 生成并检查数量**

Run: `python tools/generate_luts.py`
Run: `(Get-ChildItem FilterCam/Resources/LUTs/*.png).Count`
Expected: 输出 `generated 43 LUTs`，文件数为 43（42 款滤镜 + identity）。

- [ ] **Step 4: 抽查一张 LUT 的尺寸**

Run: `python -c "from PIL import Image; im=Image.open('FilterCam/Resources/LUTs/sim_chrome.png'); print(im.size, im.mode)"`
Expected: `(1024, 32) RGBA`。

- [ ] **Step 5: 提交**

```bash
git add tools/generate_luts.py FilterCam/Resources/LUTs
git commit -m "feat: LUT 生成脚本与 43 张 32³ 滤镜资源"
git push origin main
```

---

### Task 9: LUT 加载器

**Files:**
- Create: `FilterCam/Filter/LUTLoader.swift`
- Create: `FilterCamTests/LUTLoaderTests.swift`

**Interfaces:**
- Consumes: `FilterCam/Resources/LUTs/*.png`。
- Produces:
  - `enum LUTError: Error, Equatable { case missingResource(String), invalidImage(String), invalidData(String) }`
  - `protocol LUTLoading { func colorCube(named name: String) throws -> CIColorCube }`
  - `final class LUTLoader: LUTLoading`，`static let dimension = 32`，线程安全缓存。

- [ ] **Step 1: 写失败测试**

`FilterCamTests/LUTLoaderTests.swift`：

```swift
import CoreImage
import XCTest
@testable import FilterCam

final class LUTLoaderTests: XCTestCase {
    func testLoadsEveryPresetLUT() throws {
        let loader = LUTLoader()
        let names = PresetCatalog.all.compactMap(\.lutName)
        XCTAssertEqual(names.count, 42)
        for name in names {
            let cube = try loader.colorCube(named: name)
            XCTAssertEqual(cube.dimension, 32, "\(name) 维度错误")
            XCTAssertEqual(cube.cubeData?.count, 32 * 32 * 32 * 4 * 4, "\(name) 数据长度错误")
        }
    }

    func testMissingResourceThrows() {
        let loader = LUTLoader()
        XCTAssertThrowsError(try loader.colorCube(named: "does_not_exist")) { error in
            XCTAssertEqual(error as? LUTError, .missingResource("does_not_exist"))
        }
    }

    func testCacheReturnsEquivalentCube() throws {
        let loader = LUTLoader()
        let first = try loader.colorCube(named: "sim_chrome")
        let second = try loader.colorCube(named: "sim_chrome")
        XCTAssertEqual(first.cubeData, second.cubeData)
    }
}
```

- [ ] **Step 2: 推送确认测试失败**

Run: `git push origin main`
Expected: CI 失败，报错 `cannot find 'LUTLoader' in scope`。

- [ ] **Step 3: 写实现**

`FilterCam/Filter/LUTLoader.swift`：

```swift
import CoreImage
import CoreGraphics

enum LUTError: Error, Equatable {
    case missingResource(String)
    case invalidImage(String)
    case invalidData(String)
}

protocol LUTLoading {
    func colorCube(named name: String) throws -> CIColorCube
}

final class LUTLoader: LUTLoading {
    static let dimension = 32

    private var cache: [String: CIColorCube] = [:]
    private let lock = NSLock()

    func colorCube(named name: String) throws -> CIColorCube {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            throw LUTError.missingResource(name)
        }
        guard let image = CIImage(contentsOf: url) else {
            throw LUTError.invalidImage(name)
        }
        let expectedWidth = CGFloat(LUTLoader.dimension * LUTLoader.dimension)
        let expectedHeight = CGFloat(LUTLoader.dimension)
        guard image.extent.width == expectedWidth, image.extent.height == expectedHeight else {
            throw LUTError.invalidData(name)
        }

        let data = try Self.makeCubeData(from: image, name: name)
        let cube = CIColorCube()
        cube.dimension = Float(LUTLoader.dimension)
        cube.cubeData = data
        cache[name] = cube
        return cube
    }

    private static func makeCubeData(from image: CIImage, name: String) throws -> Data {
        let n = dimension
        let width = n * n
        let height = n
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let created = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard created else {
            throw LUTError.invalidData(name)
        }

        let count = n * n * n
        var floats = [Float](repeating: 1, count: count * 4)
        for index in 0..<count {
            let offset = index * 4
            floats[offset] = Float(bytes[offset]) / 255.0
            floats[offset + 1] = Float(bytes[offset + 1]) / 255.0
            floats[offset + 2] = Float(bytes[offset + 2]) / 255.0
            floats[offset + 3] = 1.0
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
```

说明：`CGContext.draw` 把 PNG 顶行写入内存首行，`CIColorCube` 要求索引顺序为 r 最慢、b 最快，与生成脚本的排布一致。

- [ ] **Step 4: 推送确认测试通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 5: 提交**

```bash
git add FilterCam/Filter/LUTLoader.swift FilterCamTests/LUTLoaderTests.swift
git commit -m "feat: LUT 加载器与缓存"
git push origin main
```

---

### Task 10: Core Image 滤镜管线

**Files:**
- Create: `FilterCam/Filter/FilterPipeline.swift`
- Create: `FilterCam/Filter/CoreImagePipeline.swift`
- Create: `FilterCamTests/FilterPipelineTests.swift`

**Interfaces:**
- Consumes: `FilterPreset`、`LUTLoading`、`LUTLoader`。
- Produces:
  - `protocol FilterPipeline { func process(_ image: CIImage, preset: FilterPreset, intensity: Float) -> CIImage }`
  - `final class CoreImagePipeline: FilterPipeline`，`init(lutLoader: LUTLoading, context: CIContext)`

- [ ] **Step 1: 写失败测试**

`FilterCamTests/FilterPipelineTests.swift`：

```swift
import CoreImage
import XCTest
@testable import FilterCam

final class FilterPipelineTests: XCTestCase {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private var identityPreset: FilterPreset {
        FilterPreset(
            id: "identity",
            displayName: "恒等",
            category: .simulation,
            lutName: "identity",
            grain: 0,
            vignette: 0
        )
    }

    private func solidImage(red: CGFloat = 0.4, green: CGFloat = 0.5, blue: CGFloat = 0.6) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    private func pixel(of image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }

    func testIntensityZeroReturnsOriginal() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(input, preset: identityPreset, intensity: 0)
        XCTAssertEqual(pixel(of: output), pixel(of: input))
    }

    func testIdentityLUTPreservesColor() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(input, preset: identityPreset, intensity: 1)
        let expected = pixel(of: input)
        let actual = pixel(of: output)
        for index in 0..<3 {
            let difference = abs(Int(actual[index]) - Int(expected[index]))
            XCTAssertLessThanOrEqual(difference, 2, "通道 \(index) 偏差过大")
        }
    }

    func testChromePresetChangesColor() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(input, preset: PresetCatalog.byID["sim_chrome"]!, intensity: 1)
        XCTAssertNotEqual(pixel(of: output), pixel(of: input))
    }

    func testHalfIntensitySitsBetween() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let preset = PresetCatalog.byID["sim_chrome"]!
        let half = pixel(of: pipeline.process(input, preset: preset, intensity: 0.5))
        let original = pixel(of: input)
        let full = pixel(of: pipeline.process(input, preset: preset, intensity: 1))
        XCTAssertNotEqual(half, original)
        XCTAssertNotEqual(half, full)
    }

    func testOutputExtentMatchesInput() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(input, preset: PresetCatalog.byID["sim_vivid"]!, intensity: 0.7)
        XCTAssertEqual(output.extent, input.extent)
    }
}
```

- [ ] **Step 2: 推送确认测试失败**

Run: `git push origin main`
Expected: CI 失败，报错 `cannot find 'CoreImagePipeline' in scope`。

- [ ] **Step 3: 写实现**

`FilterCam/Filter/FilterPipeline.swift`：

```swift
import CoreImage

protocol FilterPipeline {
    func process(_ image: CIImage, preset: FilterPreset, intensity: Float) -> CIImage
}
```

`FilterCam/Filter/CoreImagePipeline.swift`：

```swift
import CoreImage
import CoreImage.CIFilterBuiltins

final class CoreImagePipeline: FilterPipeline {
    private let lutLoader: LUTLoading
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    init(lutLoader: LUTLoading, context: CIContext) {
        self.lutLoader = lutLoader
        self.context = context
    }

    func process(_ image: CIImage, preset: FilterPreset, intensity: Float) -> CIImage {
        let clamped = min(max(intensity, 0), 1)
        guard let lutName = preset.lutName, clamped > 0 else {
            return image
        }

        var output = applyLUT(image, name: lutName)
        output = applyVignette(output, amount: preset.vignette)
        output = applyGrain(output, amount: preset.grain)
        output = output.cropped(to: image.extent)

        guard clamped < 1 else {
            return output
        }
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = image
        dissolve.targetImage = output
        dissolve.time = clamped
        return (dissolve.outputImage ?? output).cropped(to: image.extent)
    }

    private func applyLUT(_ image: CIImage, name: String) -> CIImage {
        guard let cube = try? lutLoader.colorCube(named: name) else {
            Log.filter.error("LUT 加载失败: \(name)")
            return image
        }
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(LUTLoader.dimension)
        filter.cubeData = cube.cubeData
        filter.colorSpace = colorSpace
        return filter.outputImage ?? image
    }

    private func applyVignette(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let filter = CIFilter.vignette()
        filter.inputImage = image
        filter.intensity = amount * 2.0
        filter.radius = 1.6
        return filter.outputImage ?? image
    }

    private func applyGrain(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let extent = image.extent
        guard let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) else {
            return image
        }
        let gray = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0
        ])
        let blended = gray.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ])
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = image
        dissolve.targetImage = blended
        dissolve.time = amount * 0.35
        return (dissolve.outputImage ?? image).cropped(to: extent)
    }
}
```

- [ ] **Step 4: 推送确认测试通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 5: 提交**

```bash
git add FilterCam/Filter FilterCamTests/FilterPipelineTests.swift
git commit -m "feat: Core Image 滤镜管线与强度混合"
git push origin main
```

---

### Task 11: 缩略图服务与滤镜偏好存储

**Files:**
- Create: `FilterCam/UI/ThumbnailService.swift`
- Create: `FilterCam/UI/FilterStore.swift`
- Create: `FilterCamTests/FilterStoreTests.swift`

**Interfaces:**
- Consumes: `FilterPipeline`、`FilterPreset`、`PresetCatalog`。
- Produces:
  - `final class ThumbnailService`，`init(pipeline:context:)`，`func generate(from:presets:size:completion:)`，回调 `[String: UIImage]`。
  - `@MainActor final class FilterStore: ObservableObject`，成员：`favorites`、`recents`、`isFavorite(_:)`、`toggleFavorite(_:)`、`markUsed(_:)`、`stripPresets`。

- [ ] **Step 1: 写失败测试**

`FilterCamTests/FilterStoreTests.swift`：

```swift
import XCTest
@testable import FilterCam

@MainActor
final class FilterStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FilterStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testToggleFavoriteAddsAndRemoves() {
        let store = FilterStore(defaults: defaults)
        store.toggleFavorite("sim_chrome")
        XCTAssertTrue(store.isFavorite("sim_chrome"))
        store.toggleFavorite("sim_chrome")
        XCTAssertFalse(store.isFavorite("sim_chrome"))
    }

    func testFavoritesAreCapped() {
        let store = FilterStore(defaults: defaults)
        for preset in PresetCatalog.all.prefix(20) {
            store.toggleFavorite(preset.id)
        }
        XCTAssertEqual(store.favorites.count, FilterStore.maxFavorites)
    }

    func testRecentsMoveToFrontAndDeduplicate() {
        let store = FilterStore(defaults: defaults)
        store.markUsed("sim_chrome")
        store.markUsed("sim_vivid")
        store.markUsed("sim_chrome")
        XCTAssertEqual(store.recents, ["sim_chrome", "sim_vivid"])
    }

    func testRecentsPersist() {
        let first = FilterStore(defaults: defaults)
        first.markUsed("sim_mono")
        let second = FilterStore(defaults: defaults)
        XCTAssertEqual(second.recents, ["sim_mono"])
    }

    func testStripStartsWithOriginalAndRespectsLimit() {
        let store = FilterStore(defaults: defaults)
        for preset in PresetCatalog.all.prefix(10) {
            store.markUsed(preset.id)
        }
        XCTAssertEqual(store.stripPresets.first, FilterPreset.original)
        XCTAssertLessThanOrEqual(store.stripPresets.count, 7)
    }
}
```

- [ ] **Step 2: 推送确认测试失败**

Run: `git push origin main`
Expected: CI 失败，报错 `cannot find 'FilterStore' in scope`。

- [ ] **Step 3: 写实现**

`FilterCam/UI/FilterStore.swift`：

```swift
import Foundation

@MainActor
final class FilterStore: ObservableObject {
    static let maxFavorites = 12
    static let maxRecents = 12
    static let stripLimit = 6

    @Published private(set) var favorites: [String]
    @Published private(set) var recents: [String]

    private let defaults: UserDefaults
    private let favoritesKey = "filter.favorites"
    private let recentsKey = "filter.recents"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.favorites = defaults.stringArray(forKey: favoritesKey) ?? []
        self.recents = defaults.stringArray(forKey: recentsKey) ?? []
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
        } else {
            favorites.insert(id, at: 0)
            if favorites.count > Self.maxFavorites {
                favorites.removeLast(favorites.count - Self.maxFavorites)
            }
        }
        defaults.set(favorites, forKey: favoritesKey)
    }

    func markUsed(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents {
            recents.removeLast(recents.count - Self.maxRecents)
        }
        defaults.set(recents, forKey: recentsKey)
    }

    var stripPresets: [FilterPreset] {
        var ids: [String] = []
        for id in favorites + recents where !ids.contains(id) {
            ids.append(id)
        }
        let presets = ids.compactMap { PresetCatalog.byID[$0] }
        return [FilterPreset.original] + presets.prefix(Self.stripLimit)
    }
}
```

`FilterCam/UI/ThumbnailService.swift`：

```swift
import CoreImage
import UIKit

final class ThumbnailService {
    private let pipeline: FilterPipeline
    private let context: CIContext
    private let queue = DispatchQueue(label: "com.filtercam.thumbnails", qos: .utility)

    init(pipeline: FilterPipeline, context: CIContext) {
        self.pipeline = pipeline
        self.context = context
    }

    func generate(
        from frame: CIImage,
        presets: [FilterPreset],
        size: CGFloat = 120,
        completion: @escaping ([String: UIImage]) -> Void
    ) {
        queue.async {
            let square = Self.centerSquare(frame, size: size)
            var result: [String: UIImage] = [:]
            for preset in presets {
                let processed = self.pipeline.process(square, preset: preset, intensity: 1)
                guard let cgImage = self.context.createCGImage(processed, from: square.extent) else {
                    continue
                }
                result[preset.id] = UIImage(cgImage: cgImage)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    static func centerSquare(_ image: CIImage, size: CGFloat) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(size / extent.width, size / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let side = size / scale
        let crop = CGRect(
            x: scaled.extent.midX - side / 2,
            y: scaled.extent.midY - side / 2,
            width: side,
            height: side
        )
        return scaled.cropped(to: crop)
    }
}
```

- [ ] **Step 4: 推送确认测试通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 5: 提交**

```bash
git add FilterCam/UI FilterCamTests/FilterStoreTests.swift
git commit -m "feat: 缩略图服务与滤镜收藏/最近使用"
git push origin main
```

---

### Task 12: 相机页接入滤镜 UI

**Files:**
- Modify: `FilterCam/UI/CameraViewModel.swift`
- Create: `FilterCam/UI/IntensitySlider.swift`
- Create: `FilterCam/UI/FilterStrip.swift`
- Create: `FilterCam/UI/FilterLibraryView.swift`
- Create: `FilterCam/UI/ShutterButton.swift`
- Create: `FilterCam/UI/ToastView.swift`
- Modify: `FilterCam/UI/CameraScreen.swift`

**Interfaces:**
- Consumes: `FilterPipeline`、`CoreImagePipeline`、`ThumbnailService`、`FilterStore`、`PresetCatalog`、`LUTLoader`。
- Produces:
  - `CameraViewModel` 新增：`selectedPreset`、`intensity`、`thumbnails`、`isLibraryPresented`、`toast`、`stripPresets`、`selectPreset(_:)`、`setIntensity(_:)`、`capture()`。
  - 视图：`IntensitySlider`、`FilterStrip`、`FilterLibraryView`、`ShutterButton`、`ToastView`。

- [ ] **Step 1: 扩展 `CameraViewModel`**

在 `FilterCam/UI/CameraViewModel.swift` 中补充以下成员与逻辑（保留 Task 6 已有内容）：

```swift
// 文件顶部 import 增加：
import UIKit

// 类内新增属性：
@Published private(set) var selectedPreset: FilterPreset = .original
@Published private(set) var intensity: Float = 1
@Published private(set) var thumbnails: [String: UIImage] = [:]
@Published var isLibraryPresented = false
@Published private(set) var toast: String?

let filterStore: FilterStore

private let filterPipeline: FilterPipeline
private let thumbnailService: ThumbnailService
private let ciContext: CIContext
private let settingsLock = NSLock()
private var settingsPreset: FilterPreset = .original
private var settingsIntensity: Float = 0
private var didCaptureThumbnailSource = false

// 初始化中新增（在绑定 camera 之前完成）：
let context = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
])
let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
self.ciContext = context
self.filterPipeline = pipeline
self.thumbnailService = ThumbnailService(pipeline: pipeline, context: context)
self.filterStore = FilterStore()

// 替换 bindCamera 中的 onFrame：
camera.onFrame = { [weak self] image in
    guard let self else { return }
    let settings = self.currentSettings()
    let output = self.filterPipeline.process(
        image,
        preset: settings.preset,
        intensity: settings.intensity
    )
    self.previewRenderer?.submit(output)
    self.captureThumbnailSource(from: image)
}

// 新增方法：
var stripPresets: [FilterPreset] {
    let base = filterStore.stripPresets
    if base.contains(selectedPreset) { return base }
    return [selectedPreset] + base.prefix(FilterStore.stripLimit)
}

func selectPreset(_ preset: FilterPreset) {
    selectedPreset = preset
    if preset.id != FilterPreset.original.id && intensity == 0 {
        intensity = 1
    }
    applySettings()
    filterStore.markUsed(preset.id)
    Haptics.selection()
}

func setIntensity(_ value: Float) {
    intensity = min(max(value, 0), 1)
    applySettings()
}

func capture() {
    Task {
        do {
            let data = try await camera.capturePhoto()
            Haptics.shutter()
            showToast("已拍摄 \(data.count / 1024) KB（保存将在下一阶段接入）")
        } catch {
            showToast(error.localizedDescription)
        }
    }
}

private func applySettings() {
    settingsLock.lock()
    settingsPreset = selectedPreset
    settingsIntensity = selectedPreset.id == FilterPreset.original.id ? 0 : intensity
    settingsLock.unlock()
}

private func currentSettings() -> (preset: FilterPreset, intensity: Float) {
    settingsLock.lock()
    defer { settingsLock.unlock() }
    return (settingsPreset, settingsIntensity)
}

private func captureThumbnailSource(from image: CIImage) {
    settingsLock.lock()
    let shouldCapture = !didCaptureThumbnailSource
    if shouldCapture { didCaptureThumbnailSource = true }
    settingsLock.unlock()
    guard shouldCapture else { return }

    thumbnailService.generate(from: image, presets: PresetCatalog.all) { [weak self] images in
        Task { @MainActor in
            self?.thumbnails.merge(images) { _, new in new }
        }
    }
}

private func showToast(_ text: String) {
    toast = text
    Task {
        try? await Task.sleep(for: .seconds(2))
        if toast == text { toast = nil }
    }
}
```

同时在 `flipCamera()` 成功后重置缩略图来源：

```swift
settingsLock.lock()
didCaptureThumbnailSource = false
settingsLock.unlock()
thumbnails.removeAll()
```

- [ ] **Step 2: 写控件**

`FilterCam/UI/IntensitySlider.swift`：

```swift
import SwiftUI

struct IntensitySlider: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 14))
                .foregroundStyle(Theme.controlDim)

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Float($0)) }
                ),
                in: 0...1
            )
            .tint(.white)

            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.control)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }
}
```

`FilterCam/UI/ShutterButton.swift`：

```swift
import SwiftUI

struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(Color.white)
                    .frame(width: 58, height: 58)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快门")
    }
}
```

`FilterCam/UI/ToastView.swift`：

```swift
import SwiftUI

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.control)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.overlay, in: Capsule())
            .transition(.opacity)
    }
}
```

- [ ] **Step 3: 写滤镜横条与滤镜库**

`FilterCam/UI/FilterStrip.swift`：

```swift
import SwiftUI

struct FilterStrip: View {
    let presets: [FilterPreset]
    let thumbnails: [String: UIImage]
    let selectedID: String
    let onSelect: (FilterPreset) -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(spacing: 6) {
                            thumbnail(for: preset)
                            Text(preset.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    selectedID == preset.id ? Theme.control : Theme.controlDim
                                )
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOpenLibrary) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.14))
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.control)
                        }
                        .frame(width: 54, height: 54)
                        Text("全部")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.controlDim)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    private func thumbnail(for preset: FilterPreset) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            if let image = thumbnails[preset.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            Circle()
                .stroke(selectedID == preset.id ? Color.white : Color.white.opacity(0.15), lineWidth: 2)
        }
        .frame(width: 54, height: 54)
        .clipShape(Circle())
    }
}
```

`FilterCam/UI/FilterLibraryView.swift`：

```swift
import SwiftUI

struct FilterLibraryView: View {
    @ObservedObject var store: FilterStore
    let thumbnails: [String: UIImage]
    let selectedID: String
    let onSelect: (FilterPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: FilterCategory = .simulation

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                categoryChips
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(PresetCatalog.presets(in: category)) { preset in
                            cell(for: preset)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("滤镜库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.control)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(category == item ? Color.black : Theme.control)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                category == item ? Color.white : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func cell(for preset: FilterPreset) -> some View {
        Button {
            onSelect(preset)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Color.white.opacity(0.10))
                    if let image = thumbnails[preset.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(
                            selectedID == preset.id ? Color.white : Color.white.opacity(0.12),
                            lineWidth: 2
                        )
                    if store.isFavorite(preset.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                Text(preset.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selectedID == preset.id ? Theme.control : Theme.controlDim)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            store.toggleFavorite(preset.id)
            Haptics.selection()
        }
    }
}
```

- [ ] **Step 4: 更新相机页布局**

`FilterCam/UI/CameraScreen.swift` 的 `body` 改为：

```swift
var body: some View {
    ZStack {
        Theme.background.ignoresSafeArea()

        if let renderer = viewModel.previewRenderer {
            CameraPreviewView(renderer: renderer)
                .ignoresSafeArea()
        }

        VStack(spacing: 0) {
            TopBar(
                flashMode: viewModel.flashMode,
                onFlash: viewModel.toggleFlash,
                onFlip: viewModel.flipCamera
            )
            .padding(.top, 8)

            Spacer()

            if viewModel.selectedPreset.id != FilterPreset.original.id {
                IntensitySlider(
                    value: viewModel.intensity,
                    onChange: viewModel.setIntensity
                )
                .padding(.bottom, 10)
            }

            ShutterButton(action: viewModel.capture)
                .padding(.bottom, 14)

            FilterStrip(
                presets: viewModel.stripPresets,
                thumbnails: viewModel.thumbnails,
                selectedID: viewModel.selectedPreset.id,
                onSelect: viewModel.selectPreset,
                onOpenLibrary: { viewModel.isLibraryPresented = true }
            )
            .padding(.bottom, 8)
        }

        overlay

        if let toast = viewModel.toast {
            VStack {
                Spacer()
                ToastView(text: toast)
                    .padding(.bottom, 190)
            }
            .allowsHitTesting(false)
        }
    }
    .sheet(isPresented: $viewModel.isLibraryPresented) {
        FilterLibraryView(
            store: viewModel.filterStore,
            thumbnails: viewModel.thumbnails,
            selectedID: viewModel.selectedPreset.id,
            onSelect: viewModel.selectPreset
        )
    }
    .onAppear(perform: viewModel.onAppear)
    .onDisappear(perform: viewModel.onDisappear)
}
```

- [ ] **Step 5: 推送确认编译通过**

Run: `git push origin main`
Expected: CI 绿灯。

- [ ] **Step 6: 真机验证**

1. 打开 App，底部出现滤镜横条与快门。
2. 点任一滤镜，取景器颜色变化，强度滑杆出现。
3. 拖动强度滑杆，效果在 0–100% 之间变化。
4. 点"全部"进入滤镜库，切换 5 个分类，每个分类都有缩略图。
5. 长按滤镜出现星标，返回后该滤镜出现在底部横条。
6. 点快门，出现"已拍摄 N KB"提示。

- [ ] **Step 7: 提交**

```bash
git add FilterCam/UI
git commit -m "feat: 滤镜横条、滤镜库、强度滑杆与快门"
git push origin main
```

---

### Task 13: 阶段一验收与文档

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-11-21-ios-filter-camera-design.md`（仅当实现与设计有偏差时）

**Interfaces:**
- 无新增接口。

- [ ] **Step 1: 跑完整真机清单**

| 检查项 | 结果 |
|---|---|
| 首次启动权限请求 | 通过 / 不通过 |
| 允许后出现实时画面 | 通过 / 不通过 |
| 拒绝后出现引导页，去设置可恢复 | 通过 / 不通过 |
| 前后摄像头切换 | 通过 / 不通过 |
| 闪光灯三态循环 | 通过 / 不通过 |
| 42 款滤镜逐一切换 | 通过 / 不通过 |
| 强度 0/50/100 | 通过 / 不通过 |
| 滤镜库 5 个分类 | 通过 / 不通过 |
| 长按收藏、最近使用 | 通过 / 不通过 |
| 快门提示出现 | 通过 / 不通过 |
| 连续切换 2 分钟无崩溃 | 通过 / 不通过 |

- [ ] **Step 2: 更新 README 的进度**

在 `README.md` 末尾追加：

```markdown
## 进度

- [x] M1 工程骨架与 CI
- [x] M2 相机预览与权限
- [x] M3 42 款 LUT 滤镜、滤镜库、强度调节
- [ ] M4 Q 版贴纸生成
- [ ] M5 编辑器与导出
- [ ] M6 验收与上架准备
```

- [ ] **Step 3: 记录真机实测帧率**

在 `docs/superpowers/specs/2026-11-21-ios-filter-camera-design.md` 第 12 节末尾追加一行实测结果，格式：

```markdown
实测：iPhone <型号>，预览 <N> fps，滤镜切换无明显卡顿。
```

- [ ] **Step 4: 提交**

```bash
git add README.md docs
git commit -m "docs: 阶段一验收记录"
git push origin main
```

- [ ] **Step 5: 确认最终 CI 状态**

Expected: `Build` 绿灯，产物可下载并安装。

---

## 阶段一完成标准

- CI 绿灯，`FilterCam-ipa` 可安装到真机。
- 相机实时预览正常，前后切换、闪光灯三态可用。
- 42 款滤镜可实时切换，强度可调，滤镜库按 5 类展示。
- 收藏与最近使用可持久化。
- 快门能成功拍摄并返回照片数据。
- 无崩溃、无明显掉帧。

阶段二（M4–M5：Q 版贴纸生成与编辑器）在阶段一验收通过后单独编写实现计划。





