# m014“破晓密令”可复现源数据

这是项目第一张不复用完整原版底图的扩展关。它仍使用 m006 的 scene
身份和第 7 关任务状态机，以保留原版“接头→双目标→撤离”闭环；但地图空间
由 `VwfBlueprintComposer` 重新合成：

- 120×200 世界切成 2×4 个城区；
- 8/8 城区全部换位；
- 五个 VWF 图层同步重排；
- 1,470/1,470 个对象及其参考坐标同步移动；
- 巡逻数组先随城区映射，再由 `mission.json` 重做关键目标和敌军路线。

`mission-package.json` 另外固定选择器第 15 关、引擎任务 7、运行时 VWF
名称、全部仓库相对路径和已经审阅的输出 SHA-256。

重新生成：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MapEditor\Missions\m014\Build-Mission.ps1
```

中间文件默认只写到系统临时目录的 `1937-vwf\m014`；也可通过
`-WorkDirectory` 指定开发工作区。源 SHA-256、区块排列、
新地表指纹和同位差异率见 `composition.md`；出生安全、任务锚点和逐段
A* 结果见 `validation.md`。
