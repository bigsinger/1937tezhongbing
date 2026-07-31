# 分析工具

这里保存本次兼容性排查使用的可复核工具源码，不属于最终游戏运行补丁。

`OriginalLevelProbe.cs` 用隔离目录启动原版，设置 1—12 关启动参数，
默认只写入原版已知的内存输入状态，不移动物理鼠标或激活窗口；同时校验
“新游戏”立即数、实际关卡全局值并截取该游戏窗口。追加 `mouseinput`
参数时会短暂激活隔离窗口、验证真实系统鼠标输入，并在结束时恢复原鼠标
位置。原始帧只在内存中
短暂存在，落盘时限制到 960 像素宽、JPEG 质量 62；若
`Invoke-LocalScreenshotOcr.ps1` 与探针程序位于同一目录，会使用 Windows
本地简体中文 OCR 生成同名 `.ocr.txt`，不上传图片。

探针地址由 `SDK/address-catalog.json` 生成，不再在 C# 中维护第二套
裸 RVA。统一编译：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\Build-Probes.ps1 `
  -OutputDirectory E:\1937\probe-build
```

也可以单独对已有压缩窗口图执行 OCR：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\Invoke-LocalScreenshotOcr.ps1 `
  -ImagePath .\original-level-01-window.jpg
```

- `GameFrameProbe.cs`：启动游戏、自动进入第一关并采集进程响应、CPU 和读取量；可选桌面画面差分；
- `ModRegressionProbe.cs --visual-capture-only`：从隔离 MOD 进程只读解析
  cnc-ddraw 的 `pvBmpBits` 导出并保存 1024×768 RGB565 主表面，同时记录
  原版相机和 1024×708 地图区；不会截取桌面、抢占焦点或发送全局输入；
- `Test-Fullscreen.ps1`：通过 cnc-ddraw 的窗口消息验证窗口/全屏尺寸切换；
- PresentMon 原始帧时间数据位于 `../results/`。测试使用 Intel PresentMon 1.10.0，仓库只保留结果，不重复分发其可执行文件。

这些工具中的地址和操作流程只适用于 [Patch README](../../README.md#目标主程序) 指定 SHA-256 的 `M1937.exe`，不应直接用于其他版本。
