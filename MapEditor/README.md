# 《1937特种兵》地图编辑器

面向原版关卡查看、修改和社区新关卡制作的可视化编辑器。

## 最简单的使用方法

1. 运行 `启动地图编辑器.ps1`；
2. 点击顶部“打开原版/工程地图”，选择 `Mod` 中任意
   `1937m000.vwf`—`1937m014.vwf`；
3. 默认选中素材库第一项“鼠标箭头（仅查看）”，浏览地图不会添加对象；
   需要编辑时再从左侧选择其他素材，在地图上单击放置；
4. 点击“另存为新地图”保存为 `*.m37map.json`。

导入原版 VWF 始终是只读操作，另存不会覆盖原始关卡。图层、对象列表和
任务链仍然可以编辑，但都放在折叠区或右侧高级页中，不影响简单流程。

## 已支持

- 直接打开和预览原版 VWF、打开现代 `*.m37map.json`；
- 直接读取 VWF 活物巡逻点，并按移动障碍层计算实际八方向路径；
- 默认显示全部路线和低开销运动预览；静态路线与动态标记分层绘制；
- 单击活物或在对象表选中后，高亮它避开墙体后的完整轨迹、路线点顺序和运动位置；
- 素材列表以“鼠标箭头（仅查看）”为第一项且默认选中，打开地图安全预览；
- 12 张原版完整地形图与 1,630+ 场景对象预览；
- 980 个角色、树木、院墙、房屋、门、车辆、障碍和物品精灵；
- 45 套地表图块；
- 地表、视线障碍、移动障碍、事件和通行修正五类图层；
- 对象放置、选择、删除和属性表；
- 任务 ID、触发器、目标、数量和后继任务；
- JSON 地图工程和任务包导出。

第 13—15 关的可复现设计分别位于 `Missions/m012`、`Missions/m013`、
`Missions/m014`。`tools/VwfMissionBuilder` 会同步改写对象坐标、巡逻数组
和动态占用格，
并对真实任务 scene、出生区以及保留/改写后的每一段巡逻路线执行 A* 校验。

第 15 关“破晓密令”还增加了 `tools/VwfBlueprintComposer`：它先按
`Missions/m014/blueprint.json` 重排 8 个地形区域，同时迁移五层网格、
场景坐标与巡逻点，再交给任务生成器部署剧情对象。编辑器可让合成地形和
原版场景精灵使用不同的素材别名，因此预览与游戏中的最终布局一致。

三个扩展关现在都由 `Missions/mNNN/mission-package.json` 描述，使用同一
入口构建并校验确定性哈希：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Build-MissionPackage.ps1 `
  -MissionId m014
```

新关模板位于 `Missions/_template`，完整流程和“能加载/能完成/可发布”的
验收边界见
[`doc/关卡制作与验证方法论.md`](../doc/关卡制作与验证方法论.md)。

素材统一放在相对目录 `Assets/Original`，通过 `catalog.json` 分类索引。
如重新运行资源解析工具，可使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Sync-OriginalAssets.ps1
```

## 开发与验证

```powershell
dotnet build .\MapEditor.slnx -c Release
$env:M1937_TEST_VWF = '..\Mod\1937m000.vwf'
$env:M1937_MAPEDITOR_ASSETS = '.\Assets\Original'
dotnet run --project .\MapEditor.Tests\MapEditor.Tests.csproj -c Release
```
