# FilterCam

iOS 胶片滤镜相机。实时预览 42 款 LUT 滤镜，支持参数微调、胶片边框与 Q 版漫画贴纸。

## 构建

本仓库没有本地 Mac 开发环境，所有构建与测试在 GitHub Actions 完成。

1. 推送代码到 `main`。
2. 打开 Actions → Build → 下载 `FilterCam-ipa` 产物。
3. Windows 上用 Sideloadly 配合 Apple ID 安装到 iPhone。

## 文档

- 设计文档：`docs/superpowers/specs/2026-11-21-ios-filter-camera-design.md`
- 实现计划：`docs/superpowers/plans/2026-11-21-filtercam-phase1.md`

## 进度

- [x] M1 工程骨架与 CI
- [x] M2 相机预览与权限
- [x] M3 42 款 LUT 滤镜、滤镜库、强度与参数调节
- [ ] M4 Q 版贴纸生成
- [ ] M5 编辑器与导出
- [ ] M6 验收与上架准备
