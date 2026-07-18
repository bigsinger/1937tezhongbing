# 十二关对白、镜头、教程、AI 配合与难度编排

## 交付结论

`m000`—`m011` 现在都有独立、可校验的数据驱动编排，合计 43 个节奏节点、45 行关内提示对白。每关至少包含：

- 开场与任务完成对白节奏；
- 引用已恢复 scene binding 的镜头提示；
- 一个需要观察玩家动作才能完成的教程门控；
- 逐关 AI 协作配置与阶段指令；
- 独立的敌人生命、伤害、反应、瞄准误差、巡逻、警报、增援和同时攻击者数值。

编排数据位于 `game/data/mission_direction.json`。`MissionDirectionData` 负责 schema 与跨目录引用验证；`MissionDirectionRuntime` 把任务事件转换为对白、镜头、教程和 AI 指令；`MissionAiCoordinator` 把逐关难度应用到敌人，并提供延迟警报共享、协同搜索小组、同时攻击者上限、确定性侧翼/压制决策和增援预算。

## 来源边界

原资源中没有发现可自动绑定到关内 scene 的逐句对白表或镜头脚本。因此本次严格分两层记录：

| 数据层 | 来源标签 | 含义 |
|---|---|---|
| 任务 ID、目标 ID、scene binding | `recovered_scene_binding` / `mixed` | 引用 `missions.json` 中由 VWF 与原程序控制流恢复的事实 |
| 对白措辞、镜头时长/缩放、教程文本、AI 策略、难度数值 | `remake_editorial` | 为复刻版可玩性新增，不能视为原版对白或原版平衡参数 |

目录顶层还固定声明 `original_dialogue_claimed=false`。校验器会拒绝把当前补写对白改标成 `recovered_transcript`，也会拒绝镜头引用不存在的目标、objective 或 scene binding。这样以后若从原版实机录像恢复到精确对白，可以逐条附证据升级，而不会混淆已经恢复的任务事实与后期创作。

## 十二关编排概览

| 关卡 | 节奏节点 | 教程门控 | AI 配合重点 | Normal 基础调校（生命/伤害/反应） |
|---|---:|---|---|---:|
| m000 营救行动 | 开场、首次营救、胜利 | 移动命令 | 教学间距、守卫营救路线 | 0.85 / 0.80 / 1.30 |
| m001 奇袭火车站 | 开场、取军服、首次爆破、胜利 | 物品背包 | 车站巡逻、首爆增援 | 0.92 / 0.88 / 1.18 |
| m002 劫狱 | 开场、救出强子、胜利 | 装备炸药 | 监牢封锁、救援后增援 | 0.96 / 0.92 / 1.12 |
| m003 铁路桥 | 开场、五点布置完成、胜利 | 连续爆破路线 | 桥面交叉火力、封锁卡车 | 1.00 / 0.96 / 1.08 |
| m004 火烧粮仓 | 开场、军官倒下、取得计划、胜利 | 角色掉落拾取 | 护卫军官、粮仓周界 | 1.02 / 1.00 / 1.04 |
| m005 大闹寒江镇 | 开场、击毙目标、胜利 | 匍匐潜入 | 城镇双人搜索、保护目标 | 1.04 / 1.02 / 1.00 |
| m006 惩罚 | 开场、到达接头点、目标处理、胜利 | 跟踪目标 | 反跟踪、封锁出口 | 1.06 / 1.04 / 0.97 |
| m007 脱困 | 开场、父母获救、全部获救、胜利 | 护送对象 | 人质封锁、截击撤离口 | 1.08 / 1.06 / 0.94 |
| m008 暗战矿坑 | 开场、布置完成、引爆、胜利 | 安全引爆顺序 | 矿坑隘口、守卫升降机 | 1.10 / 1.08 / 0.92 |
| m009 夺宝奇兵 | 开场、取得文件、清敌、胜利 | 分队与快速选择 | 车站互援、保护列车 | 1.12 / 1.10 / 0.90 |
| m010 血色渡口 | 开场、45 分钟警告、胜利 | 四人分路占点 | 四点联防、反制分队 | 1.14 / 1.12 / 0.88 |
| m011 破袭机场 | 开场、指挥官倒下、六点炸毁、胜利 | 小地图规划 | 机场纵深防御、西北封锁 | 1.16 / 1.14 / 0.86 |

“反应”是反应时间乘数，越低越快；瞄准误差乘数越低越准。生命与伤害随关卡平缓上升，反应时间、瞄准误差逐步下降，增援预算由 0 增至 5，同时攻击者上限由 2 增至 4。曲线刻意保持连续，避免单关陡增造成突兀难度墙。

## 运行时协议

### 最小接线

主场景加载关卡后创建一次导演，并将已有 `MediaDirector` 传入：

```gdscript
const MISSION_DIRECTION_RUNTIME = preload("res://scripts/mission_direction_runtime.gd")
const MISSION_AI_COORDINATOR = preload("res://scripts/mission_ai_coordinator.gd")

var direction = MISSION_DIRECTION_RUNTIME.new()
add_child(direction)
direction.configure_for_mission(level_id, media_director, difficulty_mode)
direction.camera_requested.connect(_on_direction_camera_requested)
direction.tutorial_requested.connect(_on_direction_tutorial_requested)
direction.ai_directive_requested.connect(_on_direction_ai_directive_requested)
direction.start()
```

`MediaDirector` 已具备 `start_dialogue(sequence_id, lines)`，传入后导演会直接播放文字对白；同时仍发出 `dialogue_requested`，方便字幕队列、无障碍记录或自动测试观察。

任务状态只需转发通用事件，不写逐关分支：

```gdscript
mission_runtime.objective_completed.connect(
    func(objective_id: String) -> void:
        direction.publish_event("objective_completed", {"objective_id": objective_id})
)
mission_runtime.victory.connect(func() -> void: direction.publish_event("victory"))
direction.advance_time(delta)
```

若 UI 能显示分段计数，可额外发布：

```gdscript
direction.publish_event(
    "objective_progress",
    {"objective_id": objective_id, "count": current_count}
)
```

玩家执行教程动作时调用 `report_tutorial_action()`。目标事件会被持久保存；如果目标先完成、教程动作稍后才发生，导演会在门控打开后重放待处理事实，不会永久漏掉节奏节点。

当前 `main.gd` 已完成上述产品接线：世界事件会比较目标计数并发布 `objective_progress`，目标完成、胜利和十二类教程动作均进入导演；警报由 `MissionAiCoordinator` 按本关延迟和小组上限传播，侧翼/压制确定性采样会改变搜索落点或攻击复查时机，搜索/防御/增援指令会实际唤醒受限数量的敌人。窗口化运行时播放对白与镜头，headless 及运行探针只执行状态和 AI，不打开模态媒体。

### 镜头命令

导演只发出数据，不直接争夺 `Camera2D`：

- `focus_binding`：由主场景通过当前任务的 `scene_bindings` 解析目标；
- `selection=first/last/next_incomplete/all_bounds`：选择单点或全目标包围框；
- `duration_seconds` 与 `zoom`：供可跳过的镜头插值使用；
- `follow_party`：恢复或短暂强调玩家队伍。

这种设计让镜头演出与任务判定解耦；headless、回放和无镜头模式仍能完整运行任务。

### AI 协作与难度

```gdscript
var ai = MISSION_AI_COORDINATOR.new()
add_child(ai)
ai.configure(
    direction.difficulty_profile(),
    direction.ai_cooperation_profile(),
    enemies,
)
direction.ai_directive_requested.connect(
    func(_beat_id: String, directive: Dictionary) -> void:
        ai.apply_directive(directive)
)
```

协调器提供以下确定性行为：

- 注册敌人时按本关曲线分别缩放生命、武器伤害、巡逻速度、攻击复查时间、两条等距视野半径与协同警报半径；
- `queue_shared_alert()` 按距离和 scene index 稳定排序，在本关延迟后通知有限搜索小组；
- `select_attackers()` 按距离选取并限制同时攻击者数；
- `should_flank()` / `should_use_suppressive_fire()` 用 scene index 和命令序号做无随机状态的稳定采样，支持确定性回放；
- `release_reinforcement` 只能消耗逐关预算，无法越权无限增援；`cease_reinforcement` 可永久关闭该关剩余增援。

全局 `easy/normal/hard` 不是另一套关卡数据，而是在逐关 Normal 曲线上做 ±15% 缩放；反应时间和瞄准误差因“越高越容易”而反向缩放。

## 存档与重放

`MissionDirectionRuntime.capture_state()` 保存：

- 关卡与难度模式；
- 已触发节奏节点；
- 已完成和仍显示的教程；
- 已发布的持久任务事件；
- 编排计时。

`restore_state()` 拒绝跨关卡、跨难度、未知 beat/tutorial、重复事件和非法时间。恢复本身不重播已看过的对白或镜头，后续未触发节点仍能继续正常派发。

产品存档已经把该快照和 `MissionAiCoordinator` 的姿态、剩余增援预算、禁用标志及确定性命令序号放入 `GameSessionState.world`。读取时先重建关卡和两个运行时，再恢复状态；旧版存档没有该字段，或非空快照未通过结构/关卡一致性校验时，会记录降级警告并从本关开场重新启动导演。尚未送达的亚秒级警报和一般瞬态 presentation 队列包含节点/媒体引用，不直接写入 JSON，读取后从耐久任务/AI 状态继续。

胜利演出单独保存 `victory_presentation_completed`：胜利瞬间先写入值为 `false` 的安全自动档；若此时退出，读取会只重放已经 fired 的胜利对白/镜头并恢复 `on_victory` 结局媒体，不会重复 AI、教程或任务效果。对白、影片和结局确认全部结束后，系统把标志改为 `true` 并二次自动保存；完成档不再重复演出。旧档缺少该字段时默认视为已完成，避免升级后意外重播历史演出。

## 验证

`game/tests/mission_direction_runtime_test.gd` 覆盖：

- 十二关目录与 `missions.json` 的 title/objective/binding 交叉校验；
- 每关对白、镜头、教程、AI、开场、胜利覆盖；
- 43 节奏节点与 45 行补写对白来源标签；
- 难度曲线连续性及 Easy/Normal/Hard 方向；
- 教程门控、先发生事件的回放、单次触发和定时节点；
- 同帧“目标完成 + 胜利”对白的顺序队列，防止后一句覆盖前一句；
- 存档恢复与非法快照拒绝；
- 敌人数值缩放、延迟警报小组、同时攻击上限、增援预算和确定性采样；
- 伪造原对白标签和不存在 scene binding 的负面测试。

CI 通过 `tools/Verify.ps1` 独立运行该测试，不需要原版游戏数据；套件在日志中输出当前检查数，文档不固定复制易过期计数。

## 仍需逐关实机校准的内容

当前数值和编排已经形成完整、可执行的第一版，但“调校”不是一次性静态工作。后续应基于每关完整通关录像继续记录：平均通关时长、失败原因、警报次数、弹药消耗、护送对象死亡点、每个目标前后敌人密度与镜头遮挡，再调整 `mission_direction.json`。如果取得原版逐关实机录像，应优先核对对白原文、实际镜头路径、教程出现条件和增援时机；只有附带明确证据的条目才可从 `remake_editorial` 升级为恢复内容。
