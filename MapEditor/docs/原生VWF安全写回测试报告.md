# 原生 VWF 安全写回测试报告

> 当前状态（2026-07-29）：本文下方的 15 文件结果是历史快照。实验性
> m012—m014 已撤下，当前自动测试和发行清单只覆盖 m000—m011。

## 结论

MapEditor 已能把从原版/扩展 VWF 导入的**结构内修改**安全另存为新的 VWF。
原始导入文件保持只读；工具不会通过重排未知变长记录来“猜”新格式。

## 已确认格式

- `VWL1` 世界头；
- 五个平面式网格层；
- `SLIST1` 版本 2；
- scene entity 版本 5；
- patrol 版本 1、签名 1001；
- scene 前缀、扩展尾部和四个辅助变长数组保持原长度。

## 写入事务

1. 校验导入源文件名和 SHA-256；
2. 拒绝未知版本、尺寸变化、scene 增删和巡逻容量变化；
3. 在内存副本写入五层网格、方向、世界/参考坐标、动态占用和巡逻数据；
4. 生成二进制/语义差异；
5. 在输出目录创建唯一临时文件并强制刷新；
6. 用同一解析器重新打开临时文件；
7. 比较网格、scene 槽位、记录长度、引用、辅助数组容量和编辑语义；
8. 新输出使用同卷原子移动；覆盖已有输出前先创建 `.bak`，再原子替换；
9. 任一步失败均删除临时文件，原输出保持不变。

## 自动测试

本地测试命令：

```powershell
$env:M1937_TEST_ROOT = 'E:\1937\map-editor-tests'
$env:M1937_TEST_VWF_DIRECTORY = 'F:\bigsinger\1937tezhongbing\Mod'
dotnet run --project `
  F:\bigsinger\1937tezhongbing\MapEditor\MapEditor.Tests\MapEditor.Tests.csproj `
  -c Release
```

通过项：

- m000—m014 共 15 个文件“导入 → 无修改另存”逐字节等价；
- 修改对象格坐标后，世界坐标按 32×16 网格平移；
- reference X/Y 保持与对象原相对偏移；
- `sceneIndex + 1000` 动态占用 footprint 同步平移并检查碰撞/越界；
- 巡逻 working points 与 waypoints 同步；
- 当前巡逻索引、持久标志和缓存世界坐标同步；
- 二进制区段与语义差异均能识别真实修改；
- 已有输出替换前生成内容等价的 `.bak`；
- 损坏源、越界对象、新增 scene 和巡逻容量改变均被拒绝；
- ResourceFormats 独立合成测试通过 171 项；
- MapEditor Core/Undo/Redo/质量分析测试通过。

相同 15 关矩阵已接入 Windows GitHub Actions；CI 会先按需获取 LFS 中的
VWF fixture，再执行构建和测试。
