# m012“余烬行动”源数据

本目录保存第 13 关的可复现设计源和自动验证报告：

- `mission.json`：剧情、玩家身份、活动对象部署、朝向、巡逻路线和真实
  scene 必达目标；
- `validation.md`：生成文件哈希、结构检查、出生安全及逐段 A* 结果。

重新生成：

```powershell
dotnet run --project .\MapEditor\tools\VwfMissionBuilder\VwfMissionBuilder.csproj `
  -c Release -- `
  .\Mod\1937m011.vwf `
  .\Mod\1937m012.vwf `
  .\MapEditor\Missions\m012\mission.json `
  .\MapEditor\Missions\m012\validation.md
```

生成器只进行等长字段改写：地形和场景槽位数量保持不变；对象坐标、引用
坐标、朝向、巡逻工作数组、正式路线数组和两类动态占用格会同步更新。
任何目标占用静态障碍、路线点数量改变、文件结构损坏或路径不可达都会使
生成失败。

当前出生区要求敌方初始部署和所有巡逻点至少相距 800 世界单位；输出实测
最近距离为 877。指挥官、六个爆破目标和撤离点均使用真实 scene 索引验证，
不再只检查手写的近似坐标。
