# 稳定 MOD 与 Remake 视觉等价验证

## 验证目标

静态结构测试只能证明实体、图层和资源编号没有丢失，不能证明这些数据最终
绘制在了正确的像素位置。视觉门禁因此直接比较稳定 `Mod/` 与 `Remake`
在同一关、同一原版相机坐标下的地图区输出，专门捕获以下回归：

- SPR 锚点被误当成图片中心；
- 背景、普通深度、前景和顶层队列顺序错误；
- 尚未激活的残毁效果或隐藏触发器被提前绘制；
- 地图边缘相机夹取错误；
- 黑块、透明度丢失或地图对象漏绘。

它验证的是地图和静态世界的可见等价，不冒充角色逐帧动画、HUD、任务演出
或完整通关等价；这些仍由运行轨迹和产品输入门禁分别验证。

## 输入隔离

`Patch/analysis/tools/ModRegressionProbe.cs --visual-capture-only` 从目标进程
模块导出表解析 cnc-ddraw 的 `pvBmpBits`，用 `ReadProcessMemory` 只读复制
1024×768 RGB565 主表面。探针同时读取原版相机、地图视口和玩家位置，但：

- 不截取桌面；
- 不移动、锁定、裁剪或隐藏系统光标；
- 不调用全局键盘、鼠标或焦点 API；
- 只向隔离副本的目标窗口投递进入关卡所需的进程局部消息。

Remake 侧由 `game/tests/visual_parity_probe.gd` 创建屏幕外窗口，关闭正常产品
控制器的逐帧相机夹取后，按原版的 1024×708 地图区坐标渲染。相机是否包含
玩家只记录为诊断；有些原版关卡本来就以远景开场，不能被误判为失败。

现代视口不能让不安全的原版内部画布直接扩展到 1920×1080，否则原版会产生
黑块和混合图层。工具改为让 Remake 一次渲染 1920×1080，再用原版安全的
1024×768 主表面在四个相机位置分块取证。隔离探针通过 SDK 中已恢复的原版
`sub_44A870` 相机 setter 移动视口；该函数会同步地形、前景和辅助视口，不会
操纵系统鼠标。m009 的原版视口带 302 像素内部原点，工具按原版实际夹取结果
映射到 Remake 裁剪位置，而不会把越界请求误当成画面差异。

## 一键复现

先导入稳定 MOD 的本地资源，然后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Capture-VisualParity.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe `
  -OutputDirectory .\LocalAssets\qa\visual-parity
```

脚本会为 m000—m011 逐关生成：

```text
LocalAssets/qa/visual-parity/
├─ stable-mod/<level>/02-gameplay-surface.png
├─ remake/<level>/gameplay-world.png
├─ comparison/<level>/visual-parity.json
├─ comparison/<level>/visual-parity.md
├─ comparison/<level>/visual-parity-contact-sheet.png
├─ summary.json
└─ summary.md
```

联系表从左到右为稳定 MOD、Remake、四倍绝对差。批量原图和本机 QA 结果
属于 `LocalAssets`，不会提交到 Git；仓库只保存复现工具、门限与结论。

现代 1920×1080 四分块验证：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Capture-VisualParity.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe `
  -Width 1920 -Height 1080 -TiledModernViewport `
  -OutputDirectory .\LocalAssets\qa\visual-parity-1920
```

通过的两份 `summary.json` 可压缩为不含图片和本地路径的仓库基线：

```powershell
.\tools\Build-VisualParityBaseline.ps1 `
  -SummaryPath @(
    '.\LocalAssets\qa\visual-parity-1024\summary.json',
    '.\LocalAssets\qa\visual-parity-1920\summary.json'
  )
.\tools\Test-VisualParityBaseline.ps1
```

## 门限与当前结果

世界比较区域固定为原版每个分块的 `y=48..707`：顶部 48 行头像/计时 HUD
和底部工具栏均留给独立 UI 基线，避免把“原版含 UI、Remake 隐藏
CanvasLayer”的非同类像素混入地图门禁。每个样本必须同时满足：

底部工具栏现已进入独立门禁。`PsdCompositeImage` 将 207 张原版界面 PSD
转换为本地 PNG；运行时使用 GFL 1137—1140 组成 62px 底栏，并直接采用
五名角色的选中/未选中/死亡头像以及观察、地图、系统按钮。版本化基线
`game/data/original_hud_layout_baseline.json` 固定 1024×768 和
1920×1080 的底栏、首头像和三个 50×50 按钮矩形；
`original_hud_runtime_test.gd` 用合成资源执行 144 项 HUD/覆盖层无原始数据断言，另由
`product_ui_probe.gd` 对本地真实资源生成压缩窗口图和布局 JSON。探针只读
目标视口，不操作系统鼠标。

背包、小地图、F1、暂停菜单和制作人员页已进入第二份独立静态门禁：背包直接使用 PSD 1129 的
`276×421` 底图，命中格固定为 `(13 + 50×列, 40 + 84×行)`，武器与物品
使用 50×50 普通/选中 PSD 双态；十二张 IBLOCK 地图保持原生尺寸并贴在
62px 底栏上方；F1 直接呈现居中的 IBLOCK 1047 `640×480` 原图。暂停菜单
逐行合成 PSD 1095 的 `132×38` 石纹底框与八组普通/悬停文字，1024 基准
起点为 `(207,266)`、行距为 40，并把同一中心偏移用于现代视口；制作人员页
直接显示 PSD 1254。
`original_overlay_asset_baseline.json` 固定 80 张 PNG 的 SHA-256、十二张地图
尺寸、两种桌面分辨率锚点，以及 `mouse.spr` 九个热点、16 帧和 2 tick
帧保持。真实资源门禁逐文件重算哈希，产品探针在 1024×768、1920×1080
各执行 49 项布局/可见性断言并只保存压缩目标视口图。

上述三层现在也有稳定 MOD 最终合成证据。`Capture-VisualParity.ps1` 支持
`-Overlay help|items|weapons|minimap|pause`：原版侧只向隔离进程的 DirectInput
回放队列发送一次对应快捷键，再从 cnc-ddraw 主表面读取结果；Remake 侧只
截取自己的目标视口。物品/武器、小地图和暂停菜单按原生矩形裁剪，避免把产品顶部状态
文字及不同阶段的底栏混入面板结论。PSD 1129 还按原 DirectDraw 规则恢复了
精确黑色色键、绿色数量框折线、未自动聚焦的普通图标以及 `Xn`/`n发` 文案。
五项精简结果保存在
`game/data/original_overlay_visual_parity_baselines.json`，不含原版截图或本地
路径，并由 `Test-OriginalOverlayVisualParityBaseline.ps1` 校验。

可单独复现任一层，例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Capture-VisualParity.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe `
  -Levels 1 -Overlay items `
  -OutputDirectory .\LocalAssets\qa\overlay-items
```

2026-08-03 的代表性 m000 合成结果为：

| 覆盖层 | 比较范围 | MAE | 近似像素 | 边缘相关 | 新增黑洞 |
|---|---:|---:|---:|---:|---:|
| F1 | 1024×768 整屏 | 0.042 | 99.9748% | 0.9964 | 0.0248% |
| 物品栏 | 276×421 | 4.130 | 96.3605% | 0.8691 | 0.0181% |
| 武器栏 | 276×421 | 4.134 | 96.3148% | 0.8588 | 0.0413% |
| 暂停菜单 | 132×318 | 4.454 | 96.9173% | 0.9541 | 0.0000% |
| 小地图 | 336×166 | 2.159 | 98.0081% | 0.9418 | 0.0072% |

背包边缘门限单独设为 0.85，因为原版 DirectDraw RGB565 字体光栅器无法在
Godot 中逐边缘复用；颜色 MAE、近似像素和缺失像素门限仍保持严格，底图、
图标、色键和几何也由独立哈希门禁约束。这不是放宽世界渲染门限。
尚未完成的是失败、选择器、其余顶底 HUD 以及 1920×1080 其余模态层的
逐像素合成差；这些继续保留为显式差距。

| 指标 | 门限 |
|---|---:|
| RGB 平均绝对误差 | ≤ 6/255 |
| 近似像素比例 | ≥ 92% |
| 边缘相关度 | ≥ 0.94 |
| Remake 新增黑洞比例 | ≤ 0.3% |

2026-07-31 的 12 关经典视口和现代视口基线全部通过：

| 关卡 | 1024 MAE | 1024 近似像素 | 1920 最坏 MAE | 1920 最低边缘相关度 |
|---|---:|---:|---:|---:|
| m000 | 0.626 | 99.30% | 0.796 | 0.9842 |
| m001 | 0.512 | 99.60% | 0.708 | 0.9942 |
| m002 | 0.605 | 99.42% | 1.253 | 0.9749 |
| m003 | 0.611 | 99.49% | 0.625 | 0.9909 |
| m004 | 1.047 | 98.84% | 1.409 | 0.9807 |
| m005 | 0.563 | 99.61% | 0.693 | 0.9937 |
| m006 | 0.773 | 99.25% | 1.040 | 0.9798 |
| m007 | 0.881 | 99.08% | 1.043 | 0.9786 |
| m008 | 0.562 | 99.28% | 0.637 | 0.9842 |
| m009 | 0.695 | 99.24% | 0.906 | 0.9768 |
| m010 | 0.729 | 99.17% | 1.536 | 0.9815 |
| m011 | 0.585 | 99.44% | 1.055 | 0.9840 |

现代基线共 48 个分块，零失败；全局最坏 MAE 为 1.536，最低近似像素率
98.03%，最低边缘相关度 0.9749，最高新增黑洞率 0.0287%。精简证据保存在
`game/data/visual_parity_baselines.json`，仅 24 KiB，不包含原版截图。

`tools/Test-VisualParityTool.ps1` 以合成渐变图验证比较器自身：完全相同的图像
必须通过，裁剪到现代大视口和排除工具栏后的短候选区域必须正确，人工加入的
黑洞必须失败。`tools/Test-VisualParityBaseline.ps1` 还会检查两套 12 关名单、
60 个样本、阈值、相机/裁剪映射，并拒绝本地路径或原版图片名。二者均已接入
`Verify.ps1`；完整采集需要本机稳定 MOD 资源，因此无资产 CI 只验证精简证据。

## 已由本门禁固定的实现

- 转换器把每个实体所用 SPR 第一组 `primary_triplet[0/2]` 写成
  `sprite_anchor`；真实资产测试逐一覆盖十二关 19,199 个实体和实际使用的
  704 种 SPR。
- 静态 `Sprite2D`、地面拾取物和炸药均按该原始锚点定位，不再把 VWF 坐标
  当作图片中心。
- DBL 四绘制队列保留原始背景、普通 Y 深度、前景和顶层语义。
- normal queue 的 SPR 按原版 `RowLookup` 切成 32 像素列，以
  `reference_y - primary.z + row_lookup[column]` 稳定排序；只有非均匀表
  拆分 draw item。静态对象、动态角色、门两态、拾取物、爆炸物和特殊对象
  均进入相同门禁。
- type 66/67/68/77 残毁效果在配对对象销毁前保持休眠；非可见任务触发器
  不参与正常绘制。
- 导入原版地标时不叠加 Remake 自创的大圆圈，原资源本身仍正常显示。
