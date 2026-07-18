# dinput-proxy 源码说明

这里是《1937特种兵：敌后武工队》专用 DirectInput 兼容层源码。

功能：

- 转发 `DirectInputCreateA` 到 Windows 系统 `dinput.dll`；
- 包装 DirectInput 设备接口，在旧输入轮询中处理 Windows 消息；
- 校验目标 PE 特征及原机器码后，只在进程内存中抑制资源库误报；
- 只在进程内存中跳过两个问题启动影片，不修改磁盘上的 `M1937.exe`。

使用 `build.cmd` 构建。脚本优先使用当前 PATH 中的 `cl.exe`，否则通过 Visual Studio Installer 的 `vswhere.exe` 自动定位最新 C++ 工具链，并调用 x86 Native Tools 环境。

构建目标为 32 位 DLL，因为游戏主程序是 PE32。
