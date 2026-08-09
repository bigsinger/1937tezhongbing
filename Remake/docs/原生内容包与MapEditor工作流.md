# Remake 原生内容包与 MapEditor 工作流

`.m1937pack` 是 Remake 的版本化、声明式关卡容器。它不允许携带脚本或可执行文件，
也不需要写回原版 VWF。本文描述格式、从零创作、编辑器导出、试玩、升级与故障排查。

## 1. 内容包结构

最小内容包目录如下：

```text
manifest.json
campaign.json
levels/<level-id>/level.json
levels/<level-id>/mission.json
levels/<level-id>/direction.json
```

按需还可加入 `navigation.bin`、`preview.webp`、`assets/sprites`、`assets/audio` 和
`localization`。仓库中的 `examples/synthetic-pack-source` 是完全合成、无原版资源的
最小可玩示例。机器可读规范位于 `schemas`：

- `manifest.schema.json`：包身份、版本、依赖、冲突、能力、文件长度与哈希；
- `campaign.schema.json`：关卡目录和相对入口；
- `level.schema.json`：地图尺寸、实体、巡逻路线、门、触发器和任务锚点；
- `mission.schema.json`：目标、依赖、胜负事件与场景绑定；
- `direction.schema.json`：对白、镜头、教程和 AI 指令序列。

当前 schema 版本为 1，运行时版本为 1.0.0。未知未来 schema 会被明确拒绝，
不会猜测字段含义。

## 2. 安全和确定性保证

构建器按路径字典序写入，并固定 ZIP 时间戳；相同输入会产生相同 SHA-256。
验证器在读取任何玩法内容前完成以下检查：

- 相对路径规范化，拒绝绝对路径、反斜杠、`..`、大小写碰撞和符号链接；
- 拒绝 GDScript、C#、DLL、EXE、脚本、快捷方式、PCK 等可执行内容；
- 校验 manifest 声明的每个文件长度和 SHA-256，且不得漏报或多报；
- 限制包总量、单文件、条目数、图片像素、音频时长、实体数和任务规模；
- 校验 pack ID、语义版本、最低运行时、依赖和冲突；
- 安全解压只允许写入一个已存在但为空的目标目录。

包加载失败只会产生内容诊断，不会切换关卡或写入正式存档。开发热重载仅在调试构建
启用，正式构建不会静默替换进行中的内容。

## 3. ResourceTool 命令

以下命令均从仓库根目录运行。输出应放在 `Remake/LocalAssets` 或其他 Git 忽略目录：

```powershell
dotnet run --project Remake/tools/ResourceTool -- pack build `
  Remake/examples/synthetic-pack-source `
  Remake/LocalAssets/qa/native-content/synthetic.m1937pack

dotnet run --project Remake/tools/ResourceTool -- pack validate `
  Remake/LocalAssets/qa/native-content/synthetic.m1937pack

dotnet run --project Remake/tools/ResourceTool -- pack inspect `
  Remake/LocalAssets/qa/native-content/synthetic.m1937pack

dotnet run --project Remake/tools/ResourceTool -- pack hash `
  Remake/LocalAssets/qa/native-content/synthetic.m1937pack

dotnet run --project Remake/tools/ResourceTool -- pack extract-safe `
  Remake/LocalAssets/qa/native-content/synthetic.m1937pack `
  Remake/LocalAssets/qa/native-content/extracted-empty
```

`extract-safe` 的目标必须为空，避免覆盖已有文件。

## 4. 使用 MapEditor 从零创作

1. 新建地图。素材箭头工具是默认状态，未主动选择素材时不会误放对象。
2. 设置世界尺寸、地块和地形；绘制 L2 视线遮挡与 L3 移动障碍。
3. 放置玩家、敌人、门、拾取物、撤离区等实体。每个 scene index 必须唯一。
4. 选中活物后编辑巡逻点；编辑器在画布显示完整路线和运动预览。
5. 设置任务目标、目标依赖、失败条件、撤离区和场景绑定。
6. 添加对白、镜头、教程和 AI 指令；设置物品、武器和掉落。
7. 执行可达性、出生安全和任务可完成性检查，先消除错误再导出。
8. 选择“文件 → 导出 Remake 原生内容包”，保存为 `.m1937pack`。
9. 选择“在 Remake 中试玩当前地图”。编辑器会在独立临时目录导出、校验并启动
   Godot；不会改动玩家的 `UserCampaigns` 和正常存档。

编辑器输出与 ResourceTool 使用同一 `M1937Pack` 实现，因此手工构建与一键导出的
哈希、安全限制和兼容语义一致。

## 5. 安装与启动

玩家将合法获得的 `.m1937pack` 放入游戏用户目录 `UserCampaigns`。启动时 Remake
发现有效包，将关卡 ID 表示为 `<pack_id>:<level_id>`。开发者也可用进程级隔离目录：

```powershell
$env:M1937_USER_CAMPAIGN_ROOT = 'F:\temp\m1937-test-campaigns'
D:\Godot\Godot_v4.7.1-stable_win64_console.exe --path Remake/game -- `
  --level=org.example.pack:training --skip-briefing --skip-level-selector
```

该环境变量只影响当前进程，不修改系统输入、配置或正式内容库。

## 6. 版本、依赖和升级

- `pack_id` 是稳定身份；版本更新不得为了覆盖旧包而更换 ID。
- `version` 与 `minimum_runtime_version` 使用语义版本。
- `dependencies` 列出必须同时安装的 pack ID；传递依赖缺失时整个依赖链安全禁用。
- `conflicts` 任意一方声明冲突时两包均禁用，并给出诊断。
- 存档记录 pack ID、版本和内容哈希。内容身份不兼容时拒绝读取，不把状态混入其他包。
- schema 升级必须新增显式迁移和回归 fixture；不得就地改变旧字段语义。

## 7. 发布边界

Git 只提交 schema、工具源码、合成示例、测试和文档。完整游戏包、原版素材、
`.m1937pack` 成品、EXE、PCK、ZIP、存档、日志、遥测和 `LocalAssets` 都不得提交。
本地打包脚本会自动包含所有已跟踪运行时代码和 schema；只有用户主动要求时才生成
绿色 ZIP。

## 8. 常见故障

| 诊断 | 含义与处理 |
|---|---|
| `manifest_identity_invalid` | ID、版本、来源声明或列表格式非法；按 schema 修正 |
| `payload_hash_mismatch` | 包已损坏或构建后被修改；重新构建 |
| `runtime_version_incompatible` | 升级 Remake，或降低内容所声明且实际需要的最低版本 |
| `missing_dependencies` | 安装缺失依赖及其正确版本 |
| `content_conflict` | 移走冲突包之一，不能靠改变文件名绕过 |
| `payload_policy_invalid` | 图片、音频、JSON、实体或任务超过安全上限 |
| `level_entry_invalid` | manifest 必须引用 `levels/<id>/level.json` |

完整实现与验收证据分别见 `ResourceFormats/M1937Pack.cs`、
`game/scripts/m1937_pack_loader.gd`、MapEditor 的 `NativeContentPackExporter.cs`、
`native_content_pack_test.gd` 和分层门禁报告。
