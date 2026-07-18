# 分析工具

这里保存本次兼容性排查使用的可复核工具源码，不属于最终游戏运行补丁。

- `GameFrameProbe.cs`：启动游戏、自动进入第一关并采集进程响应、CPU 和读取量；可选桌面画面差分；
- `Test-Fullscreen.ps1`：通过 cnc-ddraw 的窗口消息验证窗口/全屏尺寸切换；
- PresentMon 原始帧时间数据位于 `../results/`。测试使用 Intel PresentMon 1.10.0，仓库只保留结果，不重复分发其可执行文件。

这些工具中的地址和操作流程只适用于 [Patch README](../../README.md#目标主程序) 指定 SHA-256 的 `M1937.exe`，不应直接用于其他版本。
