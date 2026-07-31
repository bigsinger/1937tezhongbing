# 持续改进验收证据

本目录保存最终、体积受控的汇总报告；高频 JSONL、隔离游戏副本和截图原图
保留在本机 `E:\1937`，不提交到仓库。

最终性能基线包含 38,739 个 10 分钟采样；菜单/场景光标专项另含 1,914
个只读裁剪采样。两者均未调用、移动、锁定或捕获系统光标。

- `mod-regression-summary.md/json`：12 关十六阶段回归；
- `performance-baseline.md/json`：菜单、小/中/大地图各 10 分钟基线；
- `mission-sidecar-runtime.md/json`：只读世界快照、原生插件和存档安全；
- `launcher-configuration.md`：启动中心解析、别名冲突和输入安全；
- `cursor-operability-summary.md/json`：菜单/场景只读裁剪监测与进程内
  客户区回放，确认系统光标未被限制；
- `map-editor-validation.md`：12 张原版 VWF、1,037 项素材和功能矩阵。
- `release-package-validation.md/json`：安装/卸载、逐文件哈希、源工程
  编译、原 EXE 与原有配置恢复。

自动化只向隔离游戏窗口和进程内 DirectInput 队列发送消息。汇总明确记录
系统鼠标、系统输入和前台焦点调用次数为 0。需要复核完整原始采样时，按
仓库文档中的命令重新生成，不依赖本机绝对路径。

最终 12 关共通过 192 个阶段，未响应与光标裁剪限制均为 0；AI 搜索
38 次、重规划 128 次、脱离成功 35/35，最大 tick 为 1,325 μs，且警报后
没有采样视线外玩家的实时位置。
