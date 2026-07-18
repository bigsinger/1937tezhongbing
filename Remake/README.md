# 《1937特种兵》复刻工程

这是一个从零实现的新游戏工程，不修改、反编译后重新链接或分发原版二进制文件。游戏本体使用 Godot 4.7.1 Standard 和 typed GDScript，原版资源研究与转换工具使用 .NET 10。

当前仓库已经提供：

- 一个不依赖原版资产的 Godot 战术原型工程；
- 五人小队选择、编队移动和固定步进核心；
- `GFL` 的 1394 项安全枚举、原始 GBK 名称解码、伴随索引交叉校验和本地提取；
- 十二个正式 VWF 关卡的网格与 `SLIST1` 边界验证；
- SLF 的 126 条声音映射验证和已知版本 SHA-256 校验；
- 原版目录格式探针、合成 fixture 自测和资产泄漏守卫；
- 架构、格式研究、资产政策和分阶段路线图。

## 运行原型

使用 Godot 4.7.1 Standard 打开 `game/project.godot`，或者在命令行运行：

```powershell
godot --path .\game --editor
godot --path .\game
```

原型操作：左键选择队员，`Shift+左键` 多选，右键下达编队移动命令，`R` 重置队伍。

## 检查原版资源

本机需要 .NET 10 SDK。以下命令只读取原版目录，不提取资源：

```powershell
dotnet run --project .\tools\ResourceTool -- inspect "E:\1937\1937tzb_1229"
```

将资源提取到被 Git 忽略的 `LocalAssets`：

```powershell
.\tools\Import-OriginalAssets.cmd "E:\1937\1937tzb_1229"
```

现阶段导入器会拒绝未知哈希版本，生成版本化清单，并使用原始中文名称提取 GFL 条目。`SPR1/TLG1` 到 PNG、`SLIST1` 到关卡 JSON 的转换仍在实现中，因此当前原型使用程序化占位画面。

## 验证

```powershell
.\tools\Verify.cmd
```

验证脚本会构建 .NET 工具、运行不含原版数据的合成格式测试、检查仓库中是否误加入原版资产，并在能找到 Godot 时逐个解析 GDScript、执行 headless 逻辑测试及主场景启动测试。工程初始化版本已在 Godot 4.7.1 Standard 下通过这些检查；也可以把便携版可执行文件作为第一个参数显式传入：

```powershell
.\tools\Verify.cmd C:\path\to\Godot_v4.7.1-stable_win64.exe
```

`.cmd` 入口会为本次调用使用 `ExecutionPolicy Bypass`，不修改系统的 PowerShell 执行策略。也可以在允许脚本的终端中直接调用对应 `.ps1`。

详细设计见：

- [架构说明](docs/ARCHITECTURE.md)
- [已知资源格式](docs/RESOURCE_FORMATS.md)
- [开发路线图](docs/ROADMAP.md)
- [原版资产政策](ASSET_POLICY.md)

## 项目性质

这是非官方、非商业的技术保存与复刻研究工程。原版游戏、角色、美术、音频、地图、剧情文本及商标的权利归原权利人所有。仓库中的新代码尚未由仓库所有者指定开源许可证；在许可证落定前，不应假定获得复制、再许可或商业使用权。
