# 原版资源格式研究

> 状态：结构探针已在本地已知版本上验证。字段语义没有证据时统一使用中性名称，避免把空间索引误写成地形层之类的先入结论。

## 已知版本

`ResourceTool` 当前支持并强校验以下锚点。哈希只用于识别输入版本，不包含原版数据。

| 文件 | SHA-256 |
|---|---|
| `M1937.exe` | `F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3` |
| `1937Resources.GFL` | `A93DA9180C546A8F349F03BC6912583C5CC5511AC9458E4B910108614CA07211` |
| `InterMedia.GFL` | `3D937AAB4D3906A735B4E33280EA0F971A69B12B9B54F99E91BCA79FC438BB0D` |
| `1937Database.dbl` | `0017D8AB6A41F104BF0DE9A8282AB593B94E2BF7131038566AC281A8F15025D9` |
| `1937Sound.slf` | `258A890F8D5EAEB642C047E509479531CF1862C4D1395153EEE353C1C65EBEFB` |
| `1937m000.vwf` | `C98E4347A1E69D79566DD790059D41E653DBBC3209AC0B73E2511803091B0E5C` |

其他发行版本可以后续添加，不能在未验证时静默套用偏移。

## GFL 资源库与索引

两个文件都使用 78 字节全局头，文本以 `GFL (Game File Library) Win32/V1.0` 开始。

### `1937Resources.GFL`

第一条记录从绝对偏移 `0x4E` 开始，每条为：

```text
name[256]
attr[3]
uint32le payload_size
payload[payload_size]
```

1394 条顺序扫描后精确到达文件末尾，所有 payload 范围都已验证无越界。

### `InterMedia.GFL`

这是资源库的固定长度伴随索引，不是第二份资源包：

```text
+0    name[256]
+256  attr[3]
+259  uint32le payload_size
+263  uint32le payload_data_offset
```

每条 267 字节，`78 + 1394 × 267 = 372276` 与文件长度完全一致。`payload_data_offset` 指向 `1937Resources.GFL` 内 payload 魔数；解析器会逐条核对名称、属性、长度和偏移。

### 名称解码

```text
name[0]      = 原始 GBK 文件名字节长度 L
name[1..L]   = 混淆字节
其余         = 0

plain[i] = (cipher[i] - key[i]) & 0xff
```

25 字节密钥：

```text
34,37,5,44,1,4,19,27,49,24,45,35,2,
4,30,3,31,5,21,15,7,36,14,5,4
```

本版本最长名称恰好是 25 个 GBK 字节；1394 个名称全部能严格解码、全部唯一，扩展名与 payload 魔数一致。没有证据表明密钥循环，所以工具遇到 `L > 25` 会拒绝未知版本。

导入器使用“记录序号 + 经过 Windows 文件名清洗的原名称”，例如：

```text
0000_浅土地-砖地3.tlg
0079_草地-浅土地1.tlg
1266_重机枪（单）02.wav
```

### 精确资源构成

| 类型 | 数量 | payload 字节数 | 说明 |
|---|---:|---:|---|
| `SPR1` | 980 | 81,275,320 | 角色、物件和动画精灵 |
| `8BPS` | 207 | 14,347,924 | Adobe Photoshop PSD |
| `RIFF/WAVE` | 128 | 4,937,164 | 单声道 PCM WAV |
| `TLG1` | 45 | 685,381 | TileGroup 地表过渡资源 |
| `IBLOCK1` | 34 | 9,028,443 | UI、任务图等压缩位图候选 |

WAV 共约 128.6 秒；以 22050 Hz/16-bit 为主，少量为 8-bit 或 11025 Hz。

## SLF 声音映射

`1937Sound.slf` 的固定头为 121 字节：

```text
offset 117  uint32le count = 126
offset 121  第一条记录

每条 260 字节：
uint32le unknown_flag
char gbk_name[256]
```

126 条记录的 `unknown_flag` 当前都为 1，但语义未知，因此代码保留为 `UnknownFlag`。126 个 GBK 名称全部能映射到 GFL 的 WAV；GFL 另外有 `燃烧开始.wav` 和 `燃烧停止.wav` 两个未列入 SLF 的声音。

## VWF 正式关卡

`M1937.exe` 只引用 `1937M000.VWF`—`1937M011.VWF`。这十二个文件具有一致的 `VWL1` 结构：

```text
0..330   固定头，共 331 字节
331..    grid_width × grid_height × 20 字节
随后     ASCII "SLIST1" 和实体列表

slist_offset = 331 + grid_width * grid_height * 20
```

已确认头部字段：

```text
95   uint32 viewport_width
99   uint32 viewport_height
103  int32  viewport_left
107  int32  viewport_top
111  int32  viewport_right
115  int32  viewport_bottom
135  uint32 grid_width
139  uint32 grid_height
143  uint32 grid_cell_parameter  // 本版本为 16 或 64
```

十二关的公式全部精确命中 `SLIST1`：

| 关卡 | Grid | 参数 | SLIST 偏移 |
|---:|---|---:|---:|
| 000 | 155×140 | 64 | 434331 |
| 001 | 128×256 | 16 | 655691 |
| 002 | 100×120 | 64 | 240331 |
| 003 | 128×200 | 16 | 512331 |
| 004 | 170×200 | 16 | 680331 |
| 005 | 120×200 | 64 | 480331 |
| 006 | 120×200 | 16 | 480331 |
| 007 | 150×200 | 16 | 600331 |
| 008 | 90×120 | 16 | 216331 |
| 009 | 100×200 | 64 | 400331 |
| 010 | 150×210 | 16 | 630331 |
| 011 | 100×200 | 64 | 400331 |

每个 20 字节格网记录可以稳定读取为十个 `uint16`，但其语义仍待确认。`SLIST1` 版本为 2，是下一阶段建立实体坐标和数字资源引用的重点。

## 非正式关卡与污染文件

- `1937m012.vwf` 实际是 ZIP，内容属于 EA Sports 1997《FIFA 足球经理》中文文件；
- `1937m013.vwf`—`1937m015.vwf` 实际是 RIFF/CDXA MPEG 媒体；
- 原程序没有引用 012—015，导入器明确排除它们；
- `*.SAV` 和 `M1937.SI0` 是运行生成数据，不作为静态素材。

`1937Intro.svt` 和 `GamekingLogo.svt` 是标准 MPEG Program Stream，可以交给现代视频解码器，不需要复刻旧播放器。

## DBL、IBLOCK、SPR1 与 TLG1

已知但尚未完成转换的结构：

- DBL 的签名 NUL 位于偏移 77，后续字段为 `1、1023、2`；名称和 TLG 内部名称使用“每字节加 5、以 0x05 填充”的混淆；
- IBLOCK 的图像数据从相对偏移 849 开始，偏移 845 的长度始终等于 `resource_size - 849`；头部可以读取宽高和 16-bit 参数；
- SPR1 有三种头部变体，人物资源中可观察到动画组和帧数候选字段；
- 社区研究报告 SPR1/TLG1 使用 RGB565 和 LZO1X，并成功导出大多数精灵，但本项目仍需独立验证帧锚点、透明度、奇数宽度和少数格式变体。

研究线索：[Revora 的 Mission 1937 modding 讨论](https://forums.revora.net/topic/101296-help-mission-1937-modding-chinese-related-stuff/)。论坛附件及其中的原版提取资产不会进入本仓库。

## 下一解析目标

1. 完成 IBLOCK 的压缩像素解码，先恢复主界面或任务图；
2. 以静态物件验证 SPR1，再处理角色多方向动画；
3. 解析 TLG1 并生成地表图集；
4. 深入 `SLIST1`，建立关卡实体坐标和 DBL 数字资源映射；
5. 生成带 `schema_version` 的 PNG/WAV/JSON 中间格式，让 Godot 不直接依赖旧格式。
