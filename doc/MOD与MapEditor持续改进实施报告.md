# MOD 与 MapEditor 持续改进实施报告

本轮工作完整落实了《MOD与MapEditor持续改进评估》中 P0—P2 的建议。
第五节“暂不建议投入”的方向继续保持排除：没有恢复已停止的复刻工程、没有
无证据重写整个渲染器、没有扩大原版逻辑画布，也没有锁定、回中或移动系统
鼠标。

逐项状态和可复核证据见
[持续改进实施验收矩阵](持续改进实施验收矩阵.md)。本文说明最终架构、
运行入口、验证边界和后续维护方式。

## 1. 最终交付

### 1.1 MOD

- `SDK/address-catalog.json` 是 EXE 身份、地址和签名的唯一机器源，生成
  C++/C# 常量；CI 拒绝重复裸 RVA 和过期生成物。
- `SDK/mission-routes.json` 是 1—15 关的唯一关卡路由源，代理、启动中心
  和回归探针共同使用。
- 15 关保留原版“新游戏 → 任务简报 → 点击/Enter → 地图”流程；JSON
  文案预先绘制为 640×480 RGB565/IBLOCK，原游戏在原任务图片位置显示，
  不创建额外窗口，也不模拟鼠标。
- GFL 索引 1048—1059 原位替换为十二张文字图，第 13—15 关追加三个
  独立资源；`Patch/tools/Update-TextBriefings.ps1` 可从
  `Mod/关卡名称.json` 确定性重建并成对替换两份 GFL。
- `Patch/src/dinput-proxy/dinput_proxy.cpp` 提供版本保护的兼容补丁、
  结构化诊断、分通道性能遥测、进程内输入回放、按键别名和有界敌军 AI。
- 现代启动中心提供显示、渲染、难度、AI、诊断、遥测、任务 sidecar、
  原生插件和按键别名设置；全部写入 `rungame.ini`，原版菜单仍是兜底入口。
- AI 只使用警报发生时的最后目击快照；增援按距离限制为 1—4 人，搜索
  2—4 个确定性邻近点，包含前向截击、反应延迟、重获目标、超时脱离和
  原版 AI 接管。它不会持续读取视线外玩家坐标。
- `MissionSidecar` 以只读进程快照推导到达、击杀、拾取、爆破、交互和
  撤离事件，执行依赖、计数、可选、限时、成功和失败目标；状态独立原子
  保存并绑定原版 SAV 的 SHA-256，不改写原存档。
- 原生插件 ABI 对 API、schema、EXE SHA-256、长度和 PE 时间戳协商；
  SDK 附带可编译 x64 示例插件。
- 自动回归覆盖 15 关的任务启动、F1、M、鼠标、AI、保存、读取、失败、
  失败后重玩和胜利共十个阶段，测试只向目标窗口和本进程 DirectInput
  队列发送输入；AI 阶段等待全部参与搜索的敌军完成搜索或超时脱离，
  汇总发现反应、增援、搜索/重规划、玩家脱离成功率和 AI tick 开销。
- 最终 15 关共通过 150 个阶段，未响应和光标裁剪限制均为 0；AI 搜索
  44 次、重规划 176 次、脱离成功 44/44，最大反应 344 ms、最大 tick
  620 μs，警报后没有采样视线外玩家的实时位置。
- 性能工具对菜单、小、中、大地图分别运行 10 分钟，记录合成器等待
  P95/P99、CPU、磁盘峰值、消息泵、输入延迟、AI tick、首载和卡顿来源。
  最终 38,739 个样本中未响应和超过 50ms 的卡顿均为 0，四组 P99 为
  9.414—12.837ms；唯一一个 25—50ms 离群点对应中地图延迟资源读取。
- m014 先修复了跨图路径与渲染/命中相机不同步；随后“真实移动”专项
  复测又证明完整区块搬移破坏了原任务 7 的未序列化拓扑：玩家无法移动，
  单逻辑核占用 87.5%。最终采用拓扑安全地表合成，5,132/24,000 格发生
  视觉变化而碰撞、事件、scene 和巡逻拓扑不变。正式回归玩家位移 72
  像素，P95/P99 8.351/12.703ms，0 次未响应和光标裁剪。详见
  [原流程文字任务简报与扩展关卡修复报告](原流程文字任务简报与扩展关卡修复报告-20260728.md)。

可玩产物仍位于 `Mod`：

```powershell
.\Mod\选择关卡.ps1
```

默认关闭实验性的任务 sidecar 与第三方插件。需要使用时，在启动中心的
“高级增强设置”中显式开启；不兼容或加载失败会记录诊断并回退到原版任务，
不会形成半启用状态。

### 1.2 MapEditor

- 对 m000—m014 原生 VWF 执行只读导入、安全另存、重解析、结构校验、
  二进制/语义 diff、原子替换和 `.bak` 备份；无修改另存逐字节等价。
- 同步世界坐标、参考坐标、五层网格、动态占用和两套巡逻点；拒绝损坏
  文件、越界坐标、scene 增删、记录长度和巡逻容量变化。
- 问题面板检查接缝、跨区块大对象、素材 footprint、孤立区、窄通道、
  不可达任务、巡逻拥堵、出生威胁、前景排序和任务状态映射；单击问题
  可定位对象或格点。
- 关卡包向导封装 redeploy/composite 流程，隔离生成候选、预览、VWF、
  报告、哈希接受记录和路由草案，不覆盖源文件。
- 完整 Undo/Redo、多选、框选、对齐、分布、复制、批量属性、画笔、
  矩形、填充、巡逻点拖拽/插入/删除、对象筛选、图层锁定/透明度/独显/
  预设和原子自动保存恢复。
- 大地图使用视口裁剪和局部重绘；120×200、1,470 对象地图在截图基线中
  只访问 1,643 个可见格、绘制 37 个对象，单帧约 11.8 ms。
- 任务依赖图、原版状态码映射、失败/撤离校验、方向扇形视线遮挡、
  听觉/攻击/警报叠加、AI 协同推演、可达热图、最短路径及玩家/巡逻
  时间轴均已实现，并在界面标明“原版恢复值”“Mod 配置值”或
  “编辑器估算”。
- 1,037 个素材均有 footprint、移动/视线遮挡、门、推荐层级、类别和
  数值来源元数据；CI 可重复生成并检查全覆盖。
- 支持跨地图区域复制与 scene/占用重绑、语义 diff、三方合并与冲突检测。
- 导入/导出插件具备 API 版本门禁；内置格式包括地图 JSON 和正式
  `.m1937mission.json`。三个发行 sidecar 已通过编辑器往返测试。
- 高级任务页完整暴露 Sidecar 身份、关卡路由、任务依赖、可选/失败目标、
  数据库对象绑定、区域与期限字段，新建任务无需再手写 JSON。
- 一键发布生成 `README.md`、SVG 缩略图、故事章节、验证摘要和机器清单。

运行每次改动后重新发布的本地成品：

```powershell
.\MapEditor\启动地图编辑器.ps1
```

入口实际启动 `MapEditor/LocalBuild/1937MapEditor.exe`。发布目录的
`build-manifest.json` 列出每个二进制的长度和 SHA-256。

## 2. 安全和兼容边界

1. 所有自动化运行在 `E:\1937` 下的隔离副本，不改动用户正在使用的
   `Mod/rungame.ini`、`Mod/M1937.cfg` 和存档。
2. 输入回放使用目标窗口私有消息和代理内部队列；系统鼠标、系统输入和
   前台焦点调用次数均为 0。源码门禁同时拒绝光标捕获/释放 API；运行
   回归只读采样 `GetClipCursor`，菜单和场景均要求限制样本为 0。
3. 前台真实鼠标只采用既有人工授权证据：
   `Patch/analysis/results/v137-scene-mouse-probe.txt`。该记录确认窗口
   边缘卷屏、系统/内部坐标跨度、静止漂移和回中误差。
4. 原版 VWF 永远只读；编辑器输出到新路径，验证通过后才原子发布。
5. Sidecar 主机只读进程内存，任务状态写到独立文件；原 SAV 写入次数为 0。
6. 所有补丁先校验受支持 EXE 身份和哨兵字节；签名失败时保持原版行为。

## 3. 可重复验证

```powershell
# SDK、地址单一来源和原生示例插件
.\SDK\build.cmd
.\SDK\tools\Test-SdkSingleSource.ps1
.\SDK\samples\mission-plugin\Build-SamplePlugin.ps1 `
  -OutputDirectory E:\1937\sample-plugin

# MOD 和启动中心
.\Patch\tools\Build-Mod.ps1
.\Patch\analysis\tools\Test-LauncherConfiguration.ps1 `
  -OutputRoot E:\1937\launcher-tests

# 15 关十阶段回归
.\Patch\analysis\tools\Test-ModRegression.ps1 `
  -LevelList 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 `
  -DurationSeconds 60 `
  -OutputRoot E:\1937\mod-regression-final

# 菜单、小/中/大地图各 10 分钟
.\Patch\analysis\tools\Test-ModPerformance.ps1 `
  -DurationSeconds 600 `
  -Profiles menu,small,medium,large `
  -OutputRoot E:\1937\mod-performance-final

# Sidecar 单元/运行时安全验证
.\Patch\tools\Build-MissionSidecar.ps1
.\Patch\analysis\tools\Test-MissionSidecarRuntime.ps1 `
  -OutputRoot E:\1937\mission-sidecar-runtime

# MapEditor 全量测试并刷新可运行成品
.\MapEditor\tools\Publish-LocalBuild.ps1
```

GitHub Actions 分成 SDK、任务 sidecar/启动中心、MapEditor 和关卡包四条
独立流水线。它们分别验证机器源、ABI、脚本安全、素材元数据可重复性、
15 张真实 VWF 的原生往返和可运行发布产物。

## 4. 证据索引

- `Patch/docs/MOD性能与AI回归验收报告.md`
- `MapEditor/docs/持续改进功能验收报告.md`
- `MapEditor/docs/原生VWF安全写回测试报告.md`
- `MapEditor/docs/地图分析与关卡包向导验收报告.md`
- `SDK/docs/任务Sidecar与原生插件开发指南.md`
- `Patch/analysis/results/continuous-improvement/`

![现代启动中心](../Screenshots/ModernLauncher-final.png)

![MapEditor 持续改进版本](../Screenshots/MapEditor-v3-continuous-improvement.jpg)

![高级任务 Sidecar 可视化编辑](../Screenshots/MapEditor-v4-sidecar-authoring.jpg)
