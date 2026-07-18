# 资产收录与本地导入策略

## 目的

本仓库采用“源码、格式说明和任务数据入库，批量原始资源由本地导入器重建”的组织方式，主要目的有两个：

1. 控制 Git 克隆、历史记录、CI artifact 和 Release 的体积；
2. 让转换过程可以用源文件哈希、版本化清单和自动测试重复验证，而不是依赖一份来源不明的预转换资源包。

这是一项工程与发布策略，不对任何文件的权属、授权、保护期限或可分发状态作法律结论。项目维护者和发布者应根据自己的素材来源、发布范围与适用规则决定最终发布内容。

## 仓库直接收录的内容

- 新编写的 Godot、C#、PowerShell 和测试源码；
- 资源格式、架构、任务恢复和开发文档；
- `game/data/missions.json` 等重新整理的数据驱动任务定义；
- 为格式测试人工生成、不能还原原始作品的微型二进制 fixture；
- 项目自行制作或明确选择收录的占位内容。

## 默认不进入 Git 的批量内容

- 原版可执行文件、安装程序和 DLL；
- `GFL/VWF/SVT/SAV/DBL/SLF/SI0` 等旧引擎文件；
- 从本地输入批量提取或转换的图片、精灵帧、地形、音频和视频；
- 光盘镜像、绿色版压缩包、IDA 数据库、反编译日志和运行存档。

这些内容默认放在仓库外，或放在已被根 `.gitignore` 排除的 `Remake/LocalAssets/`。这是默认仓库布局；如果未来要制作包含资源的发行物，应单独设计构建配置、体积预算、来源记录和发布审核流程。

## 本地导入模型

使用者选择自己的输入目录，导入器只读检查已知文件哈希，然后将规范化结果写入 `Remake/LocalAssets/`：

```text
LocalAssets/
  manifest.json
  raw/gfl/*
  converted/
    asset-manifest.json
    iblock/*.png                         34 张
    tile-atlases/*.png                   45 张
    sprites/*.png                        980 张首帧预览
    sprite-frames/<id>/sprite.json       980 份动画清单
    sprite-frames/<id>/gNNN/atlas.png    2,775 个动画组 atlas
    sprite-frames/<id>/gNNN/fNNNN.png    共 11,898 个逐帧 PNG
    audio/*.wav                          128 个
    levels/index.json
    levels/m000/ ... m011/
      terrain.png
      level.json                         十二关共 19,199 个实体
```

Godot 读取版本化 JSON 和普通 PNG/WAV，不在运行时直接解析 GFL、VWF、DBL 或 SPR。任务图保存在仓库内的 `game/data/missions.json`；它不复制旧引擎二进制脚本，而是用于新运行时的数据模型。

## 防止误提交

- 导入输出不能与输入目录重叠；
- 输出位于任意 Git 工作树内时，导入器会在写文件前调用 `git check-ignore`；
- 根 `.gitignore` 排除 `Remake/LocalAssets/`、`game/imported/` 和常见旧资源扩展名；
- `tools/Check-NoOriginalAssets.ps1` 扫描文件名、格式签名、导入目录和压缩包内容；
- CI 和常规验证只使用合成 fixture，不要求存在本地原版目录。

导入器不会上传输入或转换结果，也不执行网络下载。完成本地导入后可运行：

```powershell
.\tools\Verify.cmd
```

如果项目以后决定把某些资源直接纳入仓库，应同时记录其来源、版本、哈希、体积、转换步骤和适用的发布说明，避免破坏可复现导入流程。
