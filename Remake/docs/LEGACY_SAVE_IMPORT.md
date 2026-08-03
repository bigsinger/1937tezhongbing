# 原版 SAV/SI 存档导入

Remake 可以把原版或稳定 MOD 生成的 `*.SAV` 转换为当前 schema 1 JSON
存档，并在真实转换关卡中继续游戏。转换是单向的，不会修改原文件，也不会
把原版字节嵌入 JSON。

## 已确认的原版格式

- `SAV` 不是附加在关卡后面的少量状态，而是一份完整 VWF 世界快照；
- 关卡身份只用不会随运行变化的 L1 地表层匹配。L2/L3 会被原版写入动态
  足印，不能参与关卡身份哈希；
- SLIST 实体的 `reference_x/reference_y` 是存档时实时位置；
  方向、生死、匍匐、当前生命、当前攻击类型和巡逻游标均随实体保存；
- 版本 5 扩展字段并非连续运行时内存。ext1 是接敌状态，ext23 才是反应状态；
  导入器会分别恢复二者，并恢复路线/移动状态、目标坐标、搜索计时、尸体发现、
  中毒/催眠及换装恢复计时；
- 四个辅助容器采用结构数组布局：先保存全部 item ID，再保存全部数量，
  最后保存全部 quantity mode。数组 0 是当前背包，数组 1 是当前武器；
- 同编号 `M1937.SI#` 是无外层签名的 320×240 RGB565 IBLOCK 缩略图，
  文件在图像负载后精确结束。

导入器还会对基准 VWF 做 scene 差分，恢复已移除/新增/改变的实体、动态
增援、已掩埋尸体及其双容器、剩余地图拾取物、可爆物、镜头和能够由当前
世界状态唯一推出的任务目标。接敌状态按原目标坐标在 96 像素内匹配仍存活的
玩家或尸体；无法唯一匹配时保留坐标搜索，不捏造对象引用。

原 SAV 没有独立的通用“事件历史/已触发脚本”区。无法由世界快照唯一证明的
任务触发历史不会被猜造，导入 JSON 的
`session.world.legacy_source.mission_progress_policy` 会明确记录这一边界。
SAV 也没有保存进程全局 MSVCRT 随机流；依赖该流的后续效果从明确的兼容种子
继续，而不会伪称恢复了原进程的随机相位。
载入后可继续实际玩法；建议立即另存到十个现代手动槽之一。

## 转换但不安装

在 `Remake` 目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\tools\Import-LegacySave.ps1 `
  -SavePath ..\Mod\1937M000.SAV
```

默认输出到被 Git 忽略的：

```text
Remake/LocalBuild/ImportedSaves/legacy_000.json
Remake/LocalBuild/ImportedSaves/legacy_000.preview.png
```

脚本会按 SAV 尾号自动寻找同目录的 `M1937.SI#`。也可显式指定：

```powershell
.\tools\Import-LegacySave.ps1 `
  -SavePath D:\OldGame\1937M004.SAV `
  -GameDirectory D:\OldGame `
  -PreviewPath D:\OldGame\M1937.SI4 `
  -SlotId legacy_home_4 `
  -OutputDirectory D:\Converted1937Saves
```

`GameDirectory` 必须包含正式的 `1937m000.vwf`—`1937m011.vwf` 和
`1937Database.dbl`，否则无法安全识别关卡和实体。

## 安装到本机 Remake

追加 `-Install`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\tools\Import-LegacySave.ps1 `
  -SavePath ..\Mod\1937M000.SAV `
  -Install
```

脚本把 JSON 安装到 Godot 当前用户的
`app_userdata/1937 Remake Prototype/saves`。启动最新版试玩包，进入
“读取游戏”，选择“原版导入 000”。导入槽在读取页可见，在保存页只读；
继续游戏后请保存到“存档 1”—“存档 10”。

目标槽已存在时脚本默认拒绝覆盖。确认要替换时才使用 `-Force`。

## 开发验证

以下命令只消费三个仓库内正式测试档及本机转换资产，不控制系统鼠标：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\tools\Test-LegacySaveCompatibility.ps1 `
  -GodotExecutable D:\Godot\Godot_v4.7.1-stable_win64_console.exe
```

验证分三层：

1. 合成 SAV/SI、EOF、错误边界和辅助容器结构测试；
2. 三个正式存档转换后通过产品 `GameSaveStore` schema 校验；
3. 在对应真实关卡中应用存档，并核对角色、容器、世界对象和镜头。

完整 `tools/Verify.cmd` 已自动包含这条门禁；原二进制未由 Git LFS
物化时会明确跳过，不会拿 LFS 指针冒充通过。
