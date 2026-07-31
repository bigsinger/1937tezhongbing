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

## 门限与当前结果

比较区域固定为 `y=0..707`，排除原版底部 60 像素工具栏。每关必须同时满足：

| 指标 | 门限 |
|---|---:|
| RGB 平均绝对误差 | ≤ 6/255 |
| 近似像素比例 | ≥ 92% |
| 边缘相关度 | ≥ 0.94 |
| Remake 新增黑洞比例 | ≤ 0.3% |

2026-07-29 的十二关基线全部通过：

| 关卡 | RGB MAE | 近似像素 | 边缘相关度 | 黑洞像素 |
|---|---:|---:|---:|---:|
| m000 | 0.893 | 98.82% | 0.9776 | 0.0105% |
| m001 | 1.275 | 98.39% | 0.9619 | 0.0207% |
| m002 | 1.091 | 98.34% | 0.9795 | 0.0156% |
| m003 | 1.113 | 98.62% | 0.9642 | 0.0065% |
| m004 | 1.072 | 98.78% | 0.9862 | 0.0033% |
| m005 | 1.657 | 97.69% | 0.9651 | 0.0261% |
| m006 | 0.996 | 98.76% | 0.9837 | 0.0214% |
| m007 | 1.826 | 97.46% | 0.9562 | 0.0059% |
| m008 | 0.949 | 98.48% | 0.9710 | 0.0327% |
| m009 | 1.724 | 97.70% | 0.9448 | 0.0425% |
| m010 | 1.335 | 98.12% | 0.9497 | 0.0221% |
| m011 | 0.830 | 99.03% | 0.9862 | 0.0163% |

`tools/Test-VisualParityTool.ps1` 以合成渐变图验证比较器自身：完全相同的图像
必须通过，人工加入的黑洞必须失败。该无原始资产测试已接入 `Verify.ps1`；
完整十二关采集需要本机稳定 MOD 资源，因此不在无资产 CI 中启动原游戏。

## 已由本门禁固定的实现

- 转换器把每个实体所用 SPR 第一组 `primary_triplet[0/2]` 写成
  `sprite_anchor`；真实资产测试逐一覆盖十二关 19,199 个实体和实际使用的
  704 种 SPR。
- 静态 `Sprite2D`、地面拾取物和炸药均按该原始锚点定位，不再把 VWF 坐标
  当作图片中心。
- DBL 四绘制队列保留原始背景、普通 Y 深度、前景和顶层语义。
- type 66/67/68/77 残毁效果在配对对象销毁前保持休眠；非可见任务触发器
  不参与正常绘制。
- 导入原版地标时不叠加 Remake 自创的大圆圈，原资源本身仍正常显示。
