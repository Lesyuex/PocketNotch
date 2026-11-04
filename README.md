# PocketNotch



PocketNotch is a lightweight macOS utility that transforms your Mac’s notch into an interactive space for system monitoring, music visualization, and everyday tools.

**让 Mac 刘海成为一个轻巧、实用的交互空间。** PocketNotch 是一款 macOS 菜单栏应用，将动态岛式交互带到 Mac 屏幕顶部，并整合媒体播放、系统状态和日常工具。

![image-20261104151851256](/Users/jobeth/Library/Application Support/typora-user-images/image-20261104151851256.png)

![image-20261104151912698](/Users/jobeth/Library/Application Support/typora-user-images/image-20261104151912698.png)

![image-20261104152017182](/Users/jobeth/Library/Application Support/typora-user-images/image-20261104152017182.png)

![image-20261104152132840](/Users/jobeth/Library/Application Support/typora-user-images/image-20261104152132840.png)



![image-20261104152237692](/Users/jobeth/Library/Application Support/typora-user-images/image-20261104152237692.png)

## 功能

- 在刘海或屏幕顶部显示可交互的灵动岛，并支持悬停、展开和拖放交互。
- 展示正在播放的媒体、封面与音频可视化，并提供播放控制。
- 提供文件暂存架、剪贴板、提醒事项、日历、计时器和应用启动器等工具。
- 查看电池、系统状态、音量、亮度、天气及已连接耳机状态。
- 展示 AI 编程助手的活动状态与桌面宠物。

功能和系统权限可在应用设置中按需开启。

## 系统要求

- macOS 14 或更新版本。
- 支持刘海屏 Mac；无刘海机型和外接显示器可使用顶部悬浮岛布局。

## 下载与安装

从 [GitHub Releases](https://github.com/Lesyuex/PocketNotch/releases/latest) 下载最新 `.dmg`，打开后将 PocketNotch 拖到“应用程序”文件夹。

目前发布包只有 ad-hoc 签名，没有 Developer ID 签名和 Apple 公证。首次打开时，macOS 可能提示无法验证开发者；请只在确认下载来源可信后，通过“系统设置 → 隐私与安全性”允许打开。

## 从源码构建

需要安装 Xcode，并接受 Xcode 命令行工具许可。然后在仓库根目录运行：

```sh
./PocketNotch/scripts/build.sh
```

脚本会使用 `PocketNotch` scheme 构建 Release 版本，在 `dist/` 中生成 DMG 和 SHA-256 校验文件。若要对外分发已签名并公证的版本，需要配置 Developer ID Application 证书，并设置 `SIGN_IDENTITY` 和 `NOTARIZE_PROFILE`：

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE_PROFILE="your-notary-profile" \
./PocketNotch/scripts/build.sh
```

## 项目结构

- `PocketNotch/`：macOS 应用、资源、模块化 Swift Package、文档和构建脚本。
- `PocketNotch.xcodeproj/`：Xcode 工程及共享 scheme。
- `Tools/`：应用图标和界面预览的开发辅助脚本。

## 隐私说明

音频可视化在本机处理音频，不录制、存储或上传音频。日历、提醒事项、蓝牙、位置等功能会在需要时请求 macOS 权限；不启用相应功能时无需授予相关权限。
