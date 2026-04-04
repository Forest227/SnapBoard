# SnapBoard

macOS 截图工具，体验接近 Snipaste。截完图直接在原位进入编辑，支持标注、钉图、提取文字。

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## 功能

- **框选截图** — 高亮窗口单击，或拖动自由框选
- **全屏截图** — 一键截取整个显示器
- **截图编辑** — 截图后原位弹出编辑菜单
  - 矩形标注、高亮、文字、箭头、直线、画笔、马赛克
  - 提取文字（支持中英文 OCR）
  - 保存到下载文件夹
  - 复制到剪贴板
  - 钉住图片（浮动置顶）
- **截图历史** — 查看最近 50 张截图，支持缩放预览
- **钉图管理** — 透明度调节、鼠标穿透开关
- **全局快捷键**（可自定义）
  - 框选截图：`⌘⇧S`
  - 全屏截图：`⌘⇧F`
- **主题切换** — 跟随系统 / 浅色 / 深色
- **开机启动** — 可在设置中开启

## 系统要求

- macOS 13.0+
- 需要授权：屏幕录制、辅助功能

## 安装

下载 [最新 Release](https://github.com/Forest227/SnapBoard/releases/latest) 中的 `SnapBoard.dmg`，挂载后将 SnapBoard.app 拖入应用程序文件夹。

首次启动会请求屏幕录制和辅助功能权限。

## 从源码构建

```bash
# 直接运行
swift run

# 打包 .app
./Scripts/build_app.sh
```

打包产物输出到 `Build/SnapBoard.app`。

## 架构

| 文件 | 职责 |
|------|------|
| `AppState` | 应用状态、权限、快捷键、登录项 |
| `CaptureCoordinator` | 截图流程编排、窗口管理 |
| `SelectionOverlay` | 框选 / 全屏选择遮罩 |
| `ScreenshotEditorWindowController` | 编辑浮层、标注、OCR |
| `PinnedScreenshotWindowController` | 浮动钉图窗口 |
| `ScreenshotHistory` | 截图历史记录 |
| `ThemeManager` | 主题管理 |
| `MenuBarContentView` | 菜单栏面板 |
| `SettingsView` | 设置面板 |
