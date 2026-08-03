# 原版动态 actor 工厂与析构顺序

本页记录 `M1937.exe` 已离线确认的动态 actor 生命周期，用于约束 SDK、MOD
插件与 Remake 的共享 MSVCRT `rand()` 调用顺序。分析只读取
`E:\1937\M1937-rand.i64`，没有启动游戏、控制鼠标或尝试通关。

## type 8 / 10 部署链

`sub_456DF0` 的 attack-type 8 与 10 分支分别调用：

- `sub_44A350(x, 0, y, 84)`；
- `sub_44A350(x, 0, y, 85)`。

`sub_44A350` 先经 `sub_453850` 执行基类/派生类构造；成功解析 actor 资源并
插入管理器后，再调用 `sub_45B950(actor, 0)`。因此一个成功部署严格消费：

1. `0x00050967`：基础 idle 上限；
2. `0x00050980`：基础朝向；
3. `0x0005340B`：AI phase；
4. `0x0005358B`：reaction 上限；
5. `0x0005BBBC`：载入后的最终朝向。

稳定产品包含 actor 84/GFL 470 与 actor 85/GFL 900，故正式内容走成功工厂
路径。无原资源的合成测试仍按这条已知成功路径建模，不能把测试夹具中缺少纹理
误当成原版资源加载失败。

## 触发、actor 62 与销毁

- actor 84 的 `sub_4556B0` 检测 faction 1 活目标进入 `32×16` 椭圆；
- actor 85 的 `sub_4553B0` 推进原 world-tick 计数；
- 两者触发时先把 `+0x1CC`（索引 115）置 1，再通过
  `sub_44CDB0(..., effect 5, GFL 64)` 请求独立 actor 62；
- actor 84/85 不是 actor 62 的粒子容器，也不会原地变形为 actor 62。

actor 62 通过自己的 `sub_44A350` 成功工厂建立；其主动画、effect-10 地面
残留、effect-12 碎片和动作帧上的 effect-11/15 均属于 actor 62 生命周期。
原部署物随后由 `sub_44D8A0` 删除，依次进入派生析构 `sub_4538A0` 和基类析构
`sub_450CE0`，严格消费：

1. `0x00053655`：派生 AI phase reset；
2. `0x000537A3`：派生 reaction reset；
3. `0x00050B64`：基础 idle reset；
4. `0x00050B7D`：基础 facing reset。

因此可见顺序是“actor 84/85 五次工厂取数 → 触发时 actor 62 及其子效果工厂
取数 → actor 84/85 四次析构取数”，不能把两个 actor 合并后省略任一事务。

## Remake 门禁

`main.gd::_spawn_legacy_special_world_object` 提交部署物五次工厂事务；
`LegacySpecialWorldObject` 只保存部署、触发/计时和所有者状态；
`LegacyExplosionEffect` 独立承载 actor 62；`resolved`/`disarmed` 回调最后提交
部署物四次析构事务。存档恢复不会重复消费已经包含在全局状态中的工厂取数。

无界面门禁覆盖：

- 五个构造调用点与四个析构调用点顺序；
- actor 84 请求独立 actor 62 后才析构；
- type 10 第 100 world tick 触发；
- 活跃部署物与独立 actor 62 的物理存读恢复；
- 十二关 155 次产品世界动作、30 次物理目标恢复与完整任务事件闭环。

## 其他已接线动态对象

同一离线调用图还固定了三条常用生命周期：

- `sub_4583F0` 在丢弃命令到达目标后先以 `sub_44A350` 创建“runtime type =
  item ID”的世界物品，再从角色容器强制移除一件；敌我角色成功收取时，经
  `sub_456AB0 → sub_449DA0 → sub_44D8A0` 消费四次析构取数；
- `sub_456CD0` 在掩埋计数严格超过 100 后先标记旧尸体，随后以五次工厂取数
  创建 actor 78/GFL 64，最后才消费尸体四次析构取数；actor 78 独立复制武器
  与背包两个容器；
- 空地 S 命令首次创建唯一 actor 90/GFL 341 时消费五次工厂取数；后续点击
  只移动同一 actor，不重复构造。第一次有效观察删除标记并消费四次析构取数；
- `sub_45E2A0` 的尸体警报从最近 type 93 标记处依次创建两个 actor 6；每个
  增援各消费一次五取数工厂。Remake 的活动生成保留这两个事务，读档重建已
  存在增援时不重放工厂，随后由 actor 快照恢复 AI/路线状态。

前三条路径有无界面顺序断言；活动手动掉落物与 actor 78 的存档不会重复工厂
事务，actor 90 按原版为一次性对象而不持久化。增援重建沿用真实关卡存档回归，
并通过显式 `consume_factory_random=false` 避免重放。

## 投射物可见 actor 与命中 actor

`sub_464DF0` 分配的投射物本体是独立的 `0x44` 字节结构，不是动态 actor；
但其可见精灵仍由该结构持有的动态 actor 提供：

- effect 2 / mode 1 通过 `sub_463290` 创建 actor 57（手榴弹）；
- effect 13 / mode 3 创建 actor 80（飞镖）；
- effect 14 / mode 4 创建 actor 81（弹弓）；
- effect 1 / mode 0 没有飞行 actor；
- effect 8 经 `sub_465310 → sub_464060` 创建 actor 60 命中火花。

actor 57/80/81 和 actor 60 的成功创建都走 `sub_44A350` 的五次工厂事务。
`sub_463A00` 在命中、碰撞或终点先通过 `sub_449DA0` 删除飞行 actor，再请求
effect 8 或 effect 4；actor 60 播放结束后由 `sub_4640B0` 删除。因此飞镖和
弹弓的严格顺序是“飞行 actor 五次工厂 → 飞行 actor 四次析构 → actor 60
五次工厂 → actor 60 四次析构”；手榴弹则先析构 actor 57，再请求独立 actor
61。普通子弹只消费 actor 60 的工厂/析构事务。

Remake 的 `CombatProjectile` schema 3 显式保存当前由飞行 actor 还是 actor 60
持有视觉生命周期；读档重建节点时不重放已经包含在全局随机状态中的工厂事务，
只消费检查点之后真正发生的析构与后继创建。无界面门禁同时断言主场景共享随机
流中的 18 个 actor 80→60 调用点顺序。
