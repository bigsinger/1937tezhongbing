# 原版角色物品背包恢复

本页记录 `RuntimeActorV1 +0x228` 物品容器的证据、产品数据和运行时
语义。它与 `+0x22C` 武器容器是两套独立结构；正式十二关不得再把二者
合并成“全队共享物资”，也不得用武器 profile 的推测默认值覆盖原版开局
数据。

## 恢复结果

对稳定 MOD 的 `m000`—`m011` 分别在进入战场和稳定检查点进行只读、
进程内快照，再与逐关 runtime actor → VWF scene 身份目录关联。产品只接纳
`resolved + exact` 身份，不把 `high` 或 `unresolved` 记录猜配给 scene：

| 项目 | 数量 |
|---|---:|
| 关卡 | 12 |
| 精确身份动态角色 | 650 |
| 有序物品记录 | 538 |
| 空背包角色 | 307 |
| 玩家角色 | 27 |
| 玩家物品记录 | 74 |
| 空背包玩家 | 1 |
| 因仅为 high 而保留在证据层、未写入产品身份 | 112 |
| 未解析身份 | 10 |

第一关强子（scene `1436`）的开局物品为 `50 × 2, mode 0`，即两个
西瓜。十二关全部 650 个精确角色已经在真实转换资源测试中与对应 Godot
角色逐项核对，顺序、物品 ID、数量和 mode 均进入运行时。

固化产物：

- `validation/baselines/mod/initial-item-inventory-v1.json`：包含捕获哈希和
  逆向来源的验证基线；
- `game/data/original_initial_item_inventory.json`：随产品发布的事实源；
- `game/scripts/original_initial_item_inventory.gd`：按 level + scene 查询；
- `game/scripts/backpack_inventory.gd`：原版有序容器和 mode 语义；
- `tools/Build-ModInitialItemInventoryBaseline.ps1`：从本地只读证据可重复生成；
- `tools/Test-OriginalInitialItemInventory.ps1`：基线与产品交叉验证。

## 容器与数量 mode

`+0x228` 与 `+0x22C` 指向相同的 16 字节容器布局：

| 相对偏移 | 含义 |
|---:|---|
| `+0x00` | 物品 ID 数组地址 |
| `+0x04` | 数量数组地址 |
| `+0x08` | quantity mode 数组地址 |
| `+0x0C` | 条目数 |

`sub_4529F0` 增加物品，`sub_452BB0` 消耗物品：

- mode 0：减少数量，到零即删除条目；
- mode 1：普通调用不消耗；调用方明确强制消费时才减少并可删除；
- mode 2：减少但保留零数量条目；明确强制删除时才移除。

`BackpackInventory` 保留原顺序且拒绝重复物品 ID、非法 mode、负数量和
未知物品。丢弃属于强制消费，因此耐久诱饵也会从原角色背包转移到地面，
而不是复制一份。

## 已恢复物品与直接效果

| ID | 名称 | 已确认运行时语义 |
|---:|---|---|
| 33 | 鸡 | 世界交互/诱饵物品 |
| 46 | 弹药箱 | 对持有的物品 36 补 10；37/38/41 各补 5；43/44/45 各补 3 |
| 47 | 医药箱 | 生命直接设为 8 |
| 48 | 肉罐头 | 世界交互/诱饵物品 |
| 49 | 降头木偶 | 世界交互/诱饵物品 |
| 50 | 西瓜 | 恢复 4，最高 8 |
| 51 | 中药 | 恢复 6，最高 8 |
| 52 | 毒酒 | 世界交互/诱饵物品 |
| 53 | 汽油桶 | 可放置世界物品 |
| 54 | 日军军服 | 将角色外观/伪装状态设为 100 |
| 82 | 狗骨头 | 世界交互/诱饵物品 |
| 83 | 香烟 | 世界交互/诱饵物品 |
| 92 | 青衫 | 将角色外观/伪装状态设为 100 |
| 101 | 文件袋 | 任务物品 |

直接效果来自 `sub_457E60`、`sub_457EF0` 和 `sub_457F00`。名称及
物品栏图来自原 GFL 中对应 PSD；地面显示优先复用原 SPR（草药、狗骨头、
罐头、酒瓶、军服箱、木偶、文件袋、西瓜、香烟、医药箱和弹药箱等）。

当前 `disguise_appearance_state = 100` 已作为角色和存档的确定状态接线；
它对敌方感知的完整原版规则仍应通过后续差分实验恢复，不能凭经验把
“伪装必定完全隐身”写死。

## 拾取、丢弃、死亡与任务

- `A` 显示当前选中角色自己的背包，`W` 仍只显示武器容器；
- 点击有直接效果的物品立即使用；点击其他物品会选中它，`T` 在鼠标位置
  丢弃一份；
- 敌人到达地面诱饵后会捡起并写入自己的背包；
- `sub_456AB0` 证明角色死亡时会把 `+0x228` 物品和 `+0x22C` 武器
  全部生成到世界并清空两套容器，Remake 已遵循该顺序；
- 若精确文件袋掉落同时属于任务 `role_drop`，运行时把任务字段合并到该
  原版掉落，不再额外复制第二份文件袋；
- 角色背包、伪装状态和尚未拾取的地面物品全部随局内存档恢复。

正式关卡的 DBL 990 军服和 DBL 998 炸药已经分别写入拾取角色的
`+0x228` / `+0x22C` 容器，不再生成共享 `field_inventory`。读取早期
Remake 存档时会在角色快照恢复后折叠旧共享副本：角色容器已有同物品则
删除重复项；只有共享项的旧档会把它迁入当前选中或首名存活角色。

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\Remake\tools\Test-OriginalInitialItemInventory.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\Remake\tools\Test-OriginalWorldPickups.ps1

D:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless `
  --path .\Remake\game `
  --script res://tests/backpack_inventory_test.gd

D:\Godot\Godot_v4.7.1-stable_win64_console.exe --headless `
  --path .\Remake\game `
  --script res://tests/original_item_runtime_test.gd -- --skip-briefing
```

完整验证还会运行 `real_original_inventory_test.gd`，逐关实例化真实转换
资源，并核对 650 个角色/538 条记录、A/W 分栏和存档往返。
