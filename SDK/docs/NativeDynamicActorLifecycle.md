# 原版动态 actor 工厂与析构顺序

本页记录 `M1937.exe` 已确认的动态 actor 生命周期，用于约束 SDK、MOD
插件与 Remake 的共享 MSVCRT `rand()` 调用顺序。静态调用图由
`E:\1937\M1937-rand.i64` 恢复；成功工厂与存读档边界又由只向目标窗口发送
消息、只挂接目标进程 DirectInput 的短探针校正，没有控制全局鼠标或尝试通关。

## type 8 / 10 部署链

`sub_456DF0` 的 attack-type 8 与 10 分支分别调用：

- `sub_44A350(x, 0, y, 84)`；
- `sub_44A350(x, 0, y, 85)`。

`sub_44A350` 先经 `sub_453850` 执行基类/派生类构造。进程内短探针已经证明，
普通局内创建在成功解析 actor 资源并插入管理器后严格消费四次：

1. `0x00050967`：基础 idle 上限；
2. `0x00050980`：基础朝向；
3. `0x0005340B`：AI phase；
4. `0x0005358B`：reaction 上限。

`0x0005BBBC` 不属于普通成功工厂。它只在 `sub_45B950` 应用 SAV 中的 actor
状态时单独消费一次“载入后朝向”随机数。m010 丢弃物品的原版实测在同一
`caller_esi` 下连续命中上述四个构造点并明确没有命中 `0x0005BBBC`；m000
存读档短探针则在完整世界重建区间只命中一次 `0x0005BBBC`。

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

因此可见顺序是“actor 84/85 四次局内工厂取数 → 触发时 actor 62 及其子效果工厂
取数 → actor 84/85 四次析构取数”，不能把两个 actor 合并后省略任一事务。

## Remake 门禁

`main.gd::_spawn_legacy_special_world_object` 提交部署物四次工厂事务；
`LegacySpecialWorldObject` 只保存部署、触发/计时和所有者状态；
`LegacyExplosionEffect` 独立承载 actor 62；`resolved`/`disarmed` 回调最后提交
部署物四次析构事务。存档恢复不会重复消费已经包含在全局状态中的工厂取数。

无界面门禁覆盖：

- 四个局内构造调用点、独立 SAV 朝向调用点与四个析构调用点顺序；
- actor 84 请求独立 actor 62 后才析构；
- type 10 第 100 world tick 触发；
- 活跃部署物与独立 actor 62 的物理存读恢复；
- 十二关 155 次产品世界动作、30 次物理目标恢复与完整任务事件闭环。

## 其他已接线动态对象

同一离线调用图还固定了三条常用生命周期：

- `sub_4583F0` 在丢弃命令到达目标后先以 `sub_44A350` 创建“runtime type =
  item ID”的世界物品，再从角色容器强制移除一件；敌我角色成功收取时，经
  `sub_456AB0 → sub_449DA0 → sub_44D8A0` 消费四次析构取数；
- `sub_456CD0` 在掩埋计数严格超过 100 后先标记旧尸体，随后以四次工厂取数
  创建 actor 78/GFL 64，最后才消费尸体四次析构取数；actor 78 独立复制武器
  与背包两个容器；
- 空地 S 命令首次创建唯一 actor 90/GFL 341 时消费四次工厂取数；后续点击
  只移动同一 actor，不重复构造。第一次有效观察删除标记并消费四次析构取数；
- `sub_45E2A0` 的尸体警报从最近 type 93 标记处依次创建两个 actor 6；每个
  增援各消费一次五取数工厂。Remake 的活动生成保留这两个事务，读档重建已
  存在增援时不重放工厂，随后由 actor 快照恢复 AI/路线状态。

前三条路径有无界面顺序断言；活动手动掉落物与 actor 78 的存档不会重复工厂
事务，actor 90 按原版为一次性对象而不持久化。增援重建沿用真实关卡存档回归，
并通过显式 `consume_factory_random=false` 避免重放。

## m006 名单 actor 101

`Mission7DocumentCarrierUpdate`（`sub_459840`，RVA `0x00059840`）只在引擎
任务 7 运行。scene 1457/runtime type 15 持有物品 101 且距离首个 type 100
对象不超过 32 时，原程序按以下顺序执行：

1. 把 type 100 的当前生命字段写为 200；
2. 调用 `sub_44A350(carrier.x-16, 0, carrier.y, 101)`，消费四次成功工厂取数；
3. 从角色两个容器中移除物品 101。

DBL 1021/runtime type 101 对应 GFL 246 `放在地上的文件袋.spr`。随后
`Mission7DocumentRecipientUpdate`（`sub_4596E0`，RVA `0x000596E0`）让
scene 1460/runtime type 22 在文件袋 256 像素内直接把 actor 101 设为目标；
它不经过通用诱饵接受表、朝向或 LOS。抵达后 `sub_456AB0` 转移物品并经管理器
删除 actor 101，消费四次析构取数。

SDK 的 `Mission7Exchange.hpp` 固定两处入口、scene/runtime type、32/256
边界、`x-16` 偏移和 actor/GFL 身份。Remake 的中途存档保存 actor 101 与全局
随机状态，恢复时不重放工厂；文件袋被加藤或玩家取得后才提交析构事务。角色
任务掉落只给真实容器产生的那一份物品附加任务标签，不会在名单已经转交后从
孙大麻子的旧绑定再次合成一份。

## 投射物可见 actor 与命中 actor

`sub_464DF0` 分配的投射物本体是独立的 `0x44` 字节结构，不是动态 actor；
但其可见精灵仍由该结构持有的动态 actor 提供：

- effect 2 / mode 1 通过 `sub_463290` 创建 actor 57（手榴弹）；
- effect 13 / mode 3 创建 actor 80（飞镖）；
- effect 14 / mode 4 创建 actor 81（弹弓）；
- effect 1 / mode 0 没有飞行 actor；
- effect 8 经 `sub_465310 → sub_464060` 创建 actor 60 命中火花。

actor 57/80/81 和 actor 60 的成功创建都走 `sub_44A350` 的四次局内工厂事务。
`sub_463A00` 在命中、碰撞或终点先通过 `sub_449DA0` 删除飞行 actor，再请求
effect 8 或 effect 4；actor 60 播放结束后由 `sub_4640B0` 删除。因此飞镖和
弹弓的严格顺序是“飞行 actor 四次工厂 → 飞行 actor 四次析构 → actor 60
四次工厂 → actor 60 四次析构”；手榴弹则先析构 actor 57，再请求独立 actor
61。普通子弹只消费 actor 60 的工厂/析构事务。

Remake 的 `CombatProjectile` schema 3 显式保存当前由飞行 actor 还是 actor 60
持有视觉生命周期；读档重建节点时不重放已经包含在全局随机状态中的工厂事务，
只消费检查点之后真正发生的析构与后继创建。无界面门禁同时断言主场景共享随机
流中的 18 个 actor 80→60 调用点顺序。

## 全调用点闭包与 dormant mode 2

`SDK/dynamic-actor-lifecycle-sites.json` 现在逐项登记受支持 EXE 中
`sub_44A350` 的 19 个直接创建调用点和 `sub_449DA0` 的 20 个直接删除调用点：

- 1 个创建点属于正式关卡载入检查点，16 个属于正式局内流程，2 个只属于
  不可达的 mode 2 残影路线；
- 11 个删除点属于正式局内完成路径，5 个只在切关/效果管理器销毁仍活动对象时
  清理，3 个是资源或内存分配失败回滚，1 个只属于不可达的 mode 2；
- 正常正式局内流程没有未实现的创建或删除调用点。检查点清理仍保持显式
  `partial`，不会用“下一关会覆盖随机状态”冒充实时消费已经接线。

effect 3 会建立 actor 58，并让 `sub_4635F0/sub_4637A0` 沿路径建立攻击者类型的
残影 clone；这就是投射结构中数值为 2 的 delivery mode。它不是十二关武器：
`sub_4656C0` 的全部直接调用者只有 `sub_44CDB0` 与 `sub_456DF0`，两条路径实际
传入的 effect 并集为 `1/2/4/5/8/10/11/12/13/14/15`，不含 3；六个正式投射
profile 同样没有 mode 2。SDK 保留其数值 ABI 和不可达证据，但 Remake 不虚构
正式入口。

`Test-DynamicActorLifecycleCoverage.ps1` 对 39 个地址集合、分类汇总、源码接线
标记、effect 调用闭包和六个正式投射 profile 做 CI 校验。新增生命周期时若没有
更新证据目录和实现标记，验证会直接失败。
