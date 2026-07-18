# 《1937特种兵》复刻工程

这是一个从零实现的新游戏工程。游戏运行时使用 Godot 4.7.1 Standard 与 typed GDScript，旧资源研究和本地转换工具使用 .NET 10。

## 里程碑状态

| 层次 | 当前成果 | 尚未完成 |
|---|---|---|
| 资源格式 | 1394 个 GFL 条目；IBLOCK、TLG1、SPR1、DBL、VWF、SLIST1、SLF/WAV；L1—L5、阵营、感知、生命值、攻击和巡逻字段 | 与后续玩法相关的剩余 DBL/SLIST 扩展字段 |
| 精灵动画 | 980 个精灵、2,775 个动画组、11,898 帧全部转换；20 动作 × 9 方向语义；精确帧保持；攻击末帧命中与死亡末帧保持 | 特殊攻击对象、受伤原动作和过渡校准 |
| 关卡 | `m000`—`m011` 全部生成地形、19,199 个实体和 L2/L3 数据；玩家/敌人/护送角色动态占位 | 可破坏物和通用中立角色行为 |
| 任务 | 十二关任务图、scene 白名单、依赖/去重/限时/胜负与世界事件协议；m000 真实营救撤离闭环 | 候选角色、区域边界、对白和逐关演出校准 |
| 玩法 | A*、动态占位、巡逻/感知/追击；实际伤害、有限弹药/装填、受伤/死亡、基础警报、救援/掉落/爆破/撤离 | 背包、武器切换、投射物、声音、存档和完整演出 |

“资源和任务结构已恢复”不等于“游戏已经复刻完成”。目前已经是带真实碰撞、寻路、动态角色、实际战斗和通用任务世界事件的十二关可玩原型；十二关数据驱动目标均可达到胜利，m000 还通过了真实 scene 的营救—护送—撤离集成测试。逐关剧情演出、若干考据候选、难度和完整产品功能仍在开发中。

## 动画与任务恢复结论

SPR 动画组参数 0 已确认使用：

```text
serial_id = action_index * 9 + direction_index
```

共 20 个动作槽和 9 个方向槽，其中方向 0 为“无”，1—8 为八方向。转换器保留每组全部帧、原始顺序、锚点参数、单组横向 atlas 和逐帧 PNG，并按原版 `parameters[2] + 1` 保存和播放每帧保持 tick。玩家和敌人的移动/站立、对应武器攻击及死亡动画已经接线；攻击进入最后一帧时复核射程/视线并结算，死亡播放一次并保持末帧。当前非致命伤为 0.18 秒重制闪红/硬直，特殊投射物与动作过渡仍待恢复。

十二关的任务结构不是只能事后从零人工编排。现已从关卡锚点、原程序任务控制流和任务简报恢复出数据驱动目标图，通用状态机可以处理目标依赖、计数去重、限时、失败和最终胜利。仍需人工校准的是对白、镜头、演出先后、触发半径、AI 配合和难度节奏。详细证据与逐关结果见 [任务恢复说明](docs/MISSION_RECOVERY.md)。

## 环境要求

- Windows 10/11；
- [.NET 10 SDK](https://dotnet.microsoft.com/)；
- Godot 4.7.1 Standard（无须 .NET 版）；
- 一份与当前已知哈希版本匹配的原版目录；
- 若导入目标位于 Git 工作树中，需要命令行可调用的 Git，以检查输出目录是否已被忽略。

## 1. 检查原版目录

以下命令只读检查目录，不提取资源：

```powershell
dotnet run --project .\tools\ResourceTool -- inspect "E:\1937\1937tzb_1229"
```

已知版本的输出应包括 `Known version hashes match: True`、`GFL entries: 1394` 和 `Formal VWF levels: 12/12`。未知哈希版本不会被静默套用既有偏移。

## 2. 本地导入资源

在 `Remake` 目录运行：

```powershell
.\tools\Import-OriginalAssets.cmd "E:\1937\1937tzb_1229"
```

也可以显式指定输出目录：

```powershell
.\tools\Import-OriginalAssets.cmd "E:\1937\1937tzb_1229" "D:\Mission1937-LocalAssets"
```

等价的底层命令：

```powershell
dotnet run --project .\tools\ResourceTool --configuration Release -- `
  import "E:\1937\1937tzb_1229" ".\LocalAssets"
```

导入器会先完成版本哈希、输入/输出目录隔离和 Git 忽略规则检查。默认输出结构为：

```text
LocalAssets/
├── manifest.json                         导入记录与源版本校验结果
├── raw/gfl/                              1394 个本地提取条目
└── converted/
    ├── asset-manifest.json               资源总索引
    ├── iblock/*.png                      34 张
    ├── tile-atlases/*.png                45 张 4×4 过渡图集
    ├── sprites/*.png                     980 张首帧预览
    ├── sprite-frames/<id>/sprite.json    980 份动画清单，schema_version = 2
    ├── sprite-frames/<id>/gNNN/
    │   ├── atlas.png                     2,775 个动画组 atlas
    │   └── fNNNN.png                     共 11,898 个逐帧 PNG
    ├── audio/*.wav                       128 个
    └── levels/
        ├── index.json                    十二关索引
        └── m000/ ... m011/
            ├── terrain.png
            ├── navigation.bin            VWF L2—L5 的 M37NAV1 数据
            └── level.json                实体、巡逻点、任务锚点和导航元数据
```

批量资源不直接进入 Git 仓库，原因和边界见 [资产收录与本地导入策略](ASSET_POLICY.md)。

## 3. 运行 Godot 原型

```powershell
godot --path .\game --editor
godot --path .\game
```

直接打开某一关：

```powershell
godot --path .\game -- --level=m007
```

操作方式：

- 左键选择队员，`Shift + 左键` 多选；
- 右键下达自动绕障碍的编队寻路命令，`R` 重置队伍；
- `WASD` 或方向键平移相机；
- 中键拖动相机，滚轮缩放；
- `PageUp` / `PageDown` 切换上一关或下一关。

主场景会读取对应 `levels/mNNN/level.json`、地形、`navigation.bin`、实体预览和动画清单。缺少全部本地数据时会回退到程序化占位场景；正式地形存在但导航无效时会拒绝可能穿墙的移动命令。

## 4. 构建与验证

```powershell
.\tools\Verify.cmd
```

验证流程会扫描意外加入仓库的批量资产、构建 .NET 解决方案、运行合成格式测试，并在找到 Godot 时解析全部 GDScript、运行 headless 逻辑测试和主场景冒烟测试；本地转换资产存在时，还会追加十二关真实资源校验和 m004 高密度寻路压力测试。如果 Godot 不在 `PATH`，可传入完整路径：

```powershell
.\tools\Verify.cmd C:\path\to\Godot_v4.7.1-stable_win64.exe
```

`.cmd` 入口只为本次调用使用 `ExecutionPolicy Bypass`，不会修改系统 PowerShell 执行策略。

导入本地资源后，可再执行 12 关与全部动画清单的真实资产回归；该测试会校验 6,000 余项尺寸、层值、出生格和动画时序：

```powershell
.\tools\Run-RealAssetTests.cmd C:\path\to\Godot_v4.7.1-stable_win64_console.exe
```

## 5. 生成 Windows 本地试玩程序

本地资源导入完成后运行：

```powershell
.\tools\Build-Playable.cmd
```

脚本会在已被 Git 忽略的 `LocalBuild/1937Remake/` 生成
`Play-1937-Remake.cmd`、Windows 可执行文件、PCK 和资源目录，并自动完成一次导出产物
headless 冒烟测试。默认使用目录联接避免重复复制数百 MiB 资源；需要可移动目录时传入
`-AssetMode Copy`。完整说明见 [Windows 本地试玩包](docs/PLAYABLE_BUILD.md)。

## 文档

- [架构与本地数据流](docs/ARCHITECTURE.md)
- [已确认的资源格式](docs/RESOURCE_FORMATS.md)
- [十二关任务恢复说明](docs/MISSION_RECOVERY.md)
- [导航、视线与战斗边界](docs/NAVIGATION_AND_COMBAT.md)
- [开发路线图与里程碑边界](docs/ROADMAP.md)
- [开发环境、验证与 IDA Python 修复](docs/DEVELOPMENT.md)
- [Windows 本地试玩包](docs/PLAYABLE_BUILD.md)
- [资产收录与本地导入策略](ASSET_POLICY.md)

## 项目边界

这是非官方的技术保存与复刻工程。仓库中的新代码是否采用开源许可证，应以仓库实际出现的许可证文件为准；本说明不对原版素材的权属、授权或分发条件作判断。
