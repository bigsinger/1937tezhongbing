# 《1937特种兵：敌后武工队》现代兼容与社区开发项目

本仓库现在以“保留原版玩法、通过补丁和工具持续增强”为主线，包含三个
彼此独立的子项目：

| 目录 | 内容 |
|---|---|
| [`Mod/`](Mod/) | 完整可运行的现代增强版，含 12 个正式关卡和全部运行资源 |
| [`Patch/`](Patch/) | 可叠加到已安装原版上的轻量补丁、源码、分析和发行包 |
| [`MapEditor/`](MapEditor/) | 现代地图与任务编辑器，可导入原版 VWF |
| [`Remake/`](Remake/) | 已停止继续扩张、保留作格式研究和现代实现参考的 Godot 工程 |

## 直接玩增强版

本仓库的完整资源由 Git LFS 管理：

```powershell
git lfs install
git clone https://github.com/bigsinger/1937tezhongbing.git
cd .\1937tezhongbing\Mod
.\选择关卡.ps1
```

也可以双击 `Mod\启动游戏-窗口模式.cmd`。现代启动中心可直接选择任意
一个正式关卡，并持久化难度、敌军 AI、显示、渲染、卷屏、输入法屏蔽
和计时设置。

增强版的主要改进：

- cnc-ddraw 将旧 DirectDraw 转换为 Direct3D 9/OpenGL；
- 修复启动弹框、长时间未响应、输入消息阻塞和代理 DLL 递归加载；
- 60 FPS、VSync、高精度计时和渐进式边缘卷屏；
- 游戏窗口禁用 IME，支持现代 DPI；
- 通过难度/AI 等级扩展敌军听觉和警报协同；
- 全部 12 关可直接选择，不修改原 EXE、不伪造存档；
- 扩展逻辑视口可按当前桌面分辨率显示更多地图，不再只做 4:3 黑边拉伸；
- 设置保存在原版 `rungame.ini` 新增的 `[mod]` 段。

关卡数量审计见 [`doc/关卡数量与VWF审计.md`](doc/关卡数量与VWF审计.md)，
十二关故事见 [`doc/十二关故事.md`](doc/十二关故事.md)。

## 地图编辑器

`MapEditor` 是 .NET 10 WPF 程序，支持：

- 地表、视线障碍、移动障碍、事件、人工通行修正五层编辑；
- 敌军、玩家、门、物品和任务点放置；
- 任务触发器、目标引用、数量、失败条件和任务链；
- 原版 `VWL1/SLIST1` VWF 只读导入；
- 可进行 Git 差异比较的 `*.m37map.json` 和任务包导出。

运行已发布版本：

```powershell
.\MapEditor\启动地图编辑器.ps1
```

开发构建：

```powershell
dotnet build .\MapEditor\MapEditor.slnx -c Release
dotnet run --project .\MapEditor\MapEditor.Tests\MapEditor.Tests.csproj -c Release
```

## 轻量补丁

如果已有自己的原版目录，可使用 `Patch/release` 中的发行包。补丁安装器
会校验 `M1937.exe` 的 SHA-256，只对已验证版本安装。完整排查与实现说明
见 [`Patch/docs/1937特种兵-Win10-Win11兼容性排查与解决方案.md`](Patch/docs/1937特种兵-Win10-Win11兼容性排查与解决方案.md)。

## 原版 Mod 开发

后续原版魔改统一在 `Mod/` 维护。修改代理或现代启动中心后，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Patch\tools\Build-Mod.ps1
```

脚本会以 x86 Release 参数重新编译 `dinput.dll`，并把 DLL、关卡数据和
启动中心同步到 `Mod/`；源码构建与可玩成品不会再出现版本脱节。需要同时
重建轻量补丁发行包时执行 `Patch\tools\Build-Release.ps1`，该脚本也会
先自动更新 `Mod/`。

## 验证

- DirectInput 代理使用 Visual C++ x86 `/W4 /O2 /Brepro` 可重复构建；
- 1920×1080 扩展渲染表面已通过后台 60 秒响应探针；
- 第一关 VWF 导入验证为 155×140 网格、5 个图层、1,630 个对象；
- MapEditor Release 构建为 0 警告、0 错误，JSON 往返测试通过；
- 原版源目录只作只读取证，后续开发均在 `Mod/`。
