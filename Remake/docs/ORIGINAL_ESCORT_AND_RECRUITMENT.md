# 原版营救、招募与追随恢复

## 结论

正式关卡中的营救对象不是统一靠 `E` 键交互。原程序从
`sub_454960` 按运行时角色类型分派，在每次角色更新中自动检查指定队员、
队员的实时类型和距离。满足条件后，处理器会按对象分别切换阵营、加入玩家
命令槽或写入 `+0x23C` 追随指针。

| 关卡 | 中立对象类型 | 接近者 | 判定 | 结果 |
|---|---:|---|---|---|
| m000 | 17 / 3 | 强子 | 严格欧氏 `<128` | faction 3，追随强子 |
| m001 | 19 | 古明且实时类型为 91 | 2:1 等距椭圆 `128×64` | 保留 faction 2，追随古明 |
| m002 | 1 | 老赵且实时类型为 2 | 严格欧氏 `<128` | faction 3，强子加入可操作队伍 |
| m004 | 10 | 大牛且实时类型为 8 | 严格欧氏 `<128` | faction 3，古明加入可操作队伍 |
| m007 | 18 | 古明 | 2:1 等距椭圆 `128×64` | faction 3，追随古明 |
| m007 | 19 / 26 | 古明、强子、老赵、铁蛋，依次检查 | 2:1 等距椭圆 `48×24` | faction 3，追随首个合格队员 |

m001 的流程因此必须先取得项目 54、完成严格 101 个换装 tick，使古明从
runtime type 10 变为 91，司机才会响应。m002 与 m004 的获救对象不是护送
NPC；它们恢复为可点击、可框选、可用固定角色键定位、可切换武器并接受 A*
地面命令的玩家角色。

## 追随调度

`sub_45D260` 写入追随对象，`sub_45D330` 执行后续更新：

1. `+0x1FC` 表示仍有活动路线时直接返回，不抽随机数，也不重新寻路；
2. 路线结束后在 RVA `0x0005D47E` 消耗一次全局 MSVCRT `rand()`；
3. 非 type 56 追随者在 `rand()%10 < 5` 且距离大于 128 时使用跑动变体，
   否则继承目标的移动状态；
4. 目标死亡时沿目标自己的追随链寻找仍存活对象；
5. 目标格被动态占位时保留挂起路线，不引入固定 52/88 像素停止带或每
   0.5 秒重复 A*。

动态追随对象不存在于启动快照，因此存档恢复必须先重新绑定目标运行时索引
和调用点，再恢复随机调度的 elapsed、serial、delay 和最后命令变体。保存的
阵营来自角色通用记录，不能把所有 `rescued=true` 对象一律强制成 faction 3。

## 实现与验证入口

- 规则：[legacy_escort_rules.gd](../game/scripts/legacy_escort_rules.gd)
- 运行角色：[escort_unit.gd](../game/scripts/escort_unit.gd)
- 世界接线：[main.gd](../game/scripts/main.gd)
- 存档：[game_session_state.gd](../game/scripts/game_session_state.gd)
- SDK：[Escort.hpp](../../SDK/include/M1937SDK/Escort.hpp)
- 边界测试：[legacy_escort_rules_test.gd](../game/tests/legacy_escort_rules_test.gd)
- 真实关卡短测：[real_mission_world_loop_test.gd](../game/tests/real_mission_world_loop_test.gd)

定向运行示例：

```powershell
D:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless `
  --path .\Remake\game --max-fps 60 --disable-vsync `
  --script res://tests/real_mission_world_loop_test.gd -- `
  --skip-briefing --world-loop-level=m007
```

这些测试只操作 Godot 目标视口。它们验证几十秒内可重复的局部闭环，不尝试
让机器人完成整关战斗；真人完整通关保留为发布验收。
