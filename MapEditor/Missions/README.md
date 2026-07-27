# VWF 关卡包

每个扩展关目录都是可重复构建的“设计源”，而不是只保存最终二进制：

| 目录 | 模式 | 选择器关卡 | 引擎任务骨架 |
|---|---|---:|---:|
| `m012` | `redeploy`：完整底图重新部署 | 13 | 12 |
| `m013` | `redeploy`：完整底图重新部署 | 14 | 7 |
| `m014` | `composite`：区域重组后重新部署 | 15 | 7 |

统一构建入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MapEditor\tools\Build-MissionPackage.ps1 `
  -MissionId m014
```

构建器读取各目录的 `mission-package.json`，验证关卡编号、引擎任务、运行时
VWF 文件名和仓库相对路径；完成地形合成、任务部署、预览图更新后，输出
SHA-256 必须与清单基线一致。源文件哈希、结构、出生安全、全图连通性、
任务锚点和逐段 A* 仍由两个 C# 工具进行深层校验。

清单结构由 `mission-package.schema.json` 描述，支持 JSON Schema 的编辑器
可以直接提示必填字段和 `composite` 专属字段。

制作新关卡时复制 `_template` 中的示例文件，并遵循
[`doc/关卡制作与验证方法论.md`](../../doc/关卡制作与验证方法论.md)。
在尚未完成实机任务闭环前，不要仅凭 VWF 能载入就登记为可发布关卡。
