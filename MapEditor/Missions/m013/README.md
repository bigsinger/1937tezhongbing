# m013“锄奸行动”源数据

本目录保存第 14 关的可复现设计源和自动验证报告：

- `mission.json`：剧情、敌我身份、活动对象部署、朝向、巡逻路线和真实
  任务 scene 锚点；
- `validation.md`：生成文件哈希、结构等价、出生安全和逐段 A* 结果。

重新生成：

```powershell
dotnet run --project .\MapEditor\tools\VwfMissionBuilder\VwfMissionBuilder.csproj `
  -c Release -- `
  .\Mod\1937m006.vwf `
  .\Mod\1937m013.vwf `
  .\MapEditor\Missions\m013\mission.json `
  .\MapEditor\Missions\m013\validation.md
```

关卡复用原第 7 关的城镇地形和任务状态机，是因为该状态机原生具备
“先确认接头—再处理两名目标—最后撤离”的闭环。生成器会把全部 32 个
敌对/任务目标的初始位置和巡逻点纳入出生安全检查；未改写的巡逻路线也会
参与验证，不会成为校验盲区。
