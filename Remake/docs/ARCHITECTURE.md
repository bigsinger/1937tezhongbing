# 复刻工程架构

## 目标

复刻工程将“原版私有格式解析”和“新游戏运行时”分离。Godot 不直接理解 GFL、VWF 等旧格式；.NET 工具先把它们转换成稳定、可测试、可迁移的中间格式。

```text
合法原版目录
    │
    ▼
.NET ResourceTool
    ├── manifest.json
    ├── PNG / WAV / OGG
    └── versioned map JSON
            │
            ▼
Godot 导入层
    ├── 地图与遮挡
    ├── 精灵与动画
    ├── 音频事件
    └── 任务数据
            │
            ▼
固定 60 Hz 游戏模拟
    ├── 角色/物品/武器
    ├── 寻路与视野
    ├── AI 状态机
    └── 任务脚本
            │
            ▼
Godot 2D 渲染、输入、UI 与现代平台导出
```

## 为什么选择 Godot 4.7

本作是俯视角 2D 即时战术游戏。Godot 提供成熟的 2D 渲染、TileMap、动画、导航、音频、UI、场景编辑器和现代 Windows 导出，可以把研发重点放在原作规则和 AI，而不是重新制造通用编辑器。

项目使用 Standard 版本和 typed GDScript，减少最终运行时依赖；格式工具继续使用 .NET 10，因为 C# 对二进制解析、测试和命令行工具更合适。

## 运行时原则

- 游戏逻辑固定为 60 Hz，渲染与逻辑解耦；
- 使用固定随机种子、输入录制和状态校验值支持确定性回放；
- 原始视觉比例由逻辑画布控制，现代全屏采用桌面分辨率；
- 默认使用 Godot Compatibility renderer，兼顾学校中的旧集成显卡；
- 资源在进入关卡前异步预载，避免游玩过程中出现磁盘读取尖峰；
- 地图数据使用带 `schema_version` 的 JSON，解析器升级不强迫重写游戏系统。

## 子目录

```text
game/                       Godot 工程
tools/ResourceFormats/      私有格式读取库
tools/ResourceTool/         命令行探针与导入器
tools/ResourceFormats.Tests 合成数据测试程序
docs/                       研究与设计文档
LocalAssets/                本地转换结果，永不入库
```
