# 安装到 iPhone

本项目的 IPA 由 GitHub Actions 自动构建，产物未签名，需要用 Sideloadly 配合你的 Apple ID 重签后安装。

## 一次性准备

1. Windows 安装 [Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k)（或 iTunes），确保能识别 iPhone。
2. 下载安装 [Sideloadly](https://sideloadly.io/)。
3. 数据线连接 iPhone，手机上点「信任此电脑」。

## 每次安装

1. 打开仓库的 Actions 页面，进入最新一次成功的 `Build`。
2. 在页面底部 Artifacts 下载 `FilterCam-ipa`，解压得到 `FilterCam.ipa`。
3. 打开 Sideloadly，把 IPA 拖进窗口。
4. `Apple account` 填你的 Apple ID，点 `Start`。
5. 输入 Apple ID 密码（必要时输入双重认证验证码）。
6. 安装完成后，iPhone 打开「设置 → 通用 → VPN 与设备管理」，信任对应的开发者证书。
7. 回到桌面打开 FilterCam，允许相机权限。

## 限制

- 免费 Apple ID 签名的 App **7 天过期**，到期后重复上面的步骤重装。
- 同时最多 3 个自签 App。
- 付费开发者账号（¥688/年）签名一年有效，并可走 TestFlight。

## 常见问题

**Sideloadly 报 `Unable to connect to device`**
检查 Apple Devices 是否能识别手机；换一根支持数据传输的线。

**安装后闪退**
多半是签名证书未信任，或 iOS 版本低于 17.0。

**相机黑屏**
确认系统设置里 FilterCam 的相机权限已开启；模拟器没有摄像头，必须真机。
