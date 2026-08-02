# 对白、声音、任务简报与旧视频恢复

## 已恢复结论

媒体恢复分为“可由文件结构确定”和“必须重新编排”两层。代码不会把文件名猜测伪装成原剧情。

- GFL `Intro_000.psd`—`Intro_011.psd`（索引 1048—1059）实际是任务一至任务十二的 640×480 完整简报图，标题、历史背景和红色行动目标已经烘焙在图内；它们按序精确映射到 `m000`—`m011`。
- GFL `m1937.m01`—`m1937.m12` 是十二关的关内目标示意图。GFL 存储顺序并非任务顺序，所以目录按文件名中的 `01..12` 恢复，而不是错误地按 archive index 排序。特别地，index 1025 的原名是 `m1937.m12` 且图上有与第十二关一致的七个标记，index 1036 的原名是 `m1937.m01` 且图上有第一关的两个目标圈；本次也据此纠正了旧 `missions.json` 中首尾两关写反的 `overview_image_index`。
- `Intro_012640/800/1024.psd` 是三种分辨率的结局图；运行时按当前窗口宽度选择最接近的一张。
- GFL 有 128 个 WAV。SLF 声明其中 126 个；`燃烧开始.wav`、`燃烧停止.wav` 只存在于 GFL。目录把 128 个全部分类，不丢弃这两个例外。
- WAV 包括五名可玩角色的选择/确认语音、敌方盘问和警报、武器/命中/死亡、动物、载具、环境和界面声音。它们不是逐关剧情对白录音。
- `GamekingLogo.svt` 是 10.396733 秒的 640×480 MPEG-1/MP2 启动画面；`1937Intro.svt` 是 139.916667 秒的 640×240 MPEG-1/MP2 历史影像，原 DirectDraw 播放路径会把它纵向放大到 640×480。
- `1937m013.vwf`—`1937m015.vwf` 分别约 125.14、81.760411、267.746533 秒。抽帧确认前两段是舞蹈录像，第三段是额外 CG/演示素材；原程序不引用它们，因此标为 `unreferenced_bonus`，绝不自动当成十三至十五关或剧情过场。
- 原资源中没有发现独立字幕轨、任务对白表或能把剧情对白自动绑定到 scene index 的脚本。任务简报文字保留在图片里；新增对白运行时提供可靠 schema 和文字降级，但新的逐场对白仍需要基于原版实机流程人工编排。

上述盘点只把索引、名称、分类和来源状态写进 Git；原 WAV、简报 PNG 和转码视频始终留在被忽略的 `Remake/LocalAssets`。

## 自动生成的媒体目录

完整导入会自动生成：

```text
Remake/LocalAssets/converted/legacy-media-catalog.json
```

旧的本地导入无需重跑全部地图，可单独补建目录：

```powershell
dotnet run --project .\tools\ResourceTool -- `
  media-catalog E:\1937\1937tzb_1229 .\LocalAssets\converted
```

schema 1 包含：

- `briefings[]`：`level_id / gfl_index / resource_name / relative_path`；
- `objective_maps[]`：逐关示意图；
- `ending_images[]`：宽度和对应图片；
- `audio_cues[]`：`category / event_key / actor_key / variant_index / caption / source_status`；
- `movies[]`：用途、源格式、转码目标、原程序是否引用、尺寸、时长和取证说明。

`source_status=slf` 表示名称来自 SLF；`gfl_only` 表示声音只在 GFL。资源目录不存在或损坏时，运行时退回仓库中的纯元数据映射 `game/data/legacy_media_map.json`。

## Godot 接口与安全降级

`scripts/legacy_media_catalog.gd` 是不依赖场景树的数据接口：

```gdscript
var catalog = preload("res://scripts/legacy_media_catalog.gd").new()
catalog.configure(converted_root) # 空字符串使用 ../LocalAssets/converted

var briefing_path: String = catalog.briefing_path("m004")
var map_path: String = catalog.objective_map_path("m004")
var indices: Array[int] = catalog.sound_indices("attack_rifle")
var voice: int = catalog.select_sound_index("acknowledge", "laozhao", variant_seed)
var wav_path: String = catalog.sound_path(voice)
var intro_path: String = catalog.movie_path("historical_intro")
```

不存在的本地文件一律返回空路径；非法绝对路径、`..` 越界路径和损坏 JSON 会被拒绝，不会让主游戏崩溃。

`scripts/media_director.gd` 是可直接加到主场景的 `CanvasLayer`：

```gdscript
var media = preload("res://scripts/media_director.gd").new()
add_child(media)
media.configure(converted_root)

media.show_briefing("m004", mission_title, textual_objective_fallback)
media.play_audio_event("attack_rifle")
media.play_audio_event("acknowledge", "laozhao", command_serial)
media.play_movie("historical_intro")
```

`show_briefing()` 即使没有图片也会显示调用者提供的标题和目标文字；返回值只表示是否使用了原简报图。音频或视频缺失时方法返回 `false` 并发出 `media_unavailable`，任务逻辑继续运行。

主场景已经在每次非 headless 切关时调用 `show_briefing()`；`--skip-briefing` 可供自动探针跳过。攻击、飞镖/弹弓命中、爆炸、警报、队员选择/命令确认、死亡和 UI 确认也已经映射到原 WAV 事件。媒体导演固定创建独立音乐/环境声播放器、一个仅供模态对白使用的播放器和 8 个预热 SFX 播放器；角色语音与 SFX 在现有槽全部忙时才按需扩展，结束后复用。音乐和影片音轨进入 `Music`，对白与角色语音进入 `Voice`，武器、爆炸、环境事件和 UI 音进入 `Sfx`。因此对白不会被枪声截断，多个角色或高密度枪声/爆炸也不会再因全局池抢占而互相截断；空闲 SFX 槽仍按确定性轮询选择。简报、对白、视频和结局图都是模态层：打开时暂停任务计时、AI、移动与战斗，导演自身以 `PROCESS_MODE_WHEN_PAUSED` 继续接收输入；Enter/Space 继续，`Esc` 必须在松开时才提交关闭/跳过，以免穿透到下层系统菜单。关闭最后一个模态层时恢复打开前的 SceneTree 暂停状态，连续切换不同媒体不会产生短暂解冻。`play_movie()` 与 `start_dialogue()` 是已测试的可用框架；任务 cue 已接入少量真实流程，但没有把 logo/历史片和十二关对白全部编排完成，也没有声称恢复了逐场对白或镜头。

### 任务媒体 cue

`missions.json` 可选的 `media_cues` 让任务状态机在 `on_start`、`on_objective`、`on_story_anchor` 和 `on_victory` 调用同一个媒体导演；cue 类型可以是 `audio`、`dialogue`、`movie` 或 `ending`。所有 cue 都必须带 `source_status`：`recovered_media_mapping` 表示媒体身份/位置有原资源映射证据，`remake_editorial` 表示为可玩性新增的编排提示，`mixed` 则要求两者并存时明确承认边界。

原有 `missions.json/media_cues` 接线仍负责 m000 的教程提示与确认音、m006 仅在 `repaired` 规则启用的接头点提示、m011 的恢复结局图。严格 `original` 会屏蔽前两类 `remake_editorial` cue，但保留 m011 的 `recovered_media_mapping` 结局。除此之外，十二关第一版关内对白节奏、镜头提示和教程门控已经放入独立的 `mission_direction.json`，由 `MissionDirectionRuntime` 派发，并可直接把文字序列送入本 `MediaDirector`。该目录共 43 个节奏节点、45 行补写对白；所有补写文本均标为 `remake_editorial`，只在显式选择 `easy/normal/hard` 时创建运行时，不会宣称为原版对白。完整来源边界和逐关表见 `MISSION_DIRECTION.md`。

对白序列支持纯文字、指定 WAV 索引或按事件/角色选择音频：

```gdscript
media.start_dialogue("m000_rescue", [
  {
    "speaker": "彭欣",
    "text": "这里填写经实机核对后的对白。",
    "audio_index": 1328,
    "minimum_seconds": 1.0,
    "auto_advance": false
  },
  {
    "speaker": "老赵",
    "text": "没有语音文件时仍正常显示文字。",
    "audio_event": "acknowledge",
    "actor_key": "laozhao"
  }
])
```

每行必须有非空 `text`；`speaker`、`audio_index`、`audio_event`、`actor_key`、`minimum_seconds` 和 `auto_advance` 可选。Enter/Space 前进，松开 Esc 跳过。这样任务可以先以完整文字流程交付，之后再逐句补录或绑定合法语音，而无需改任务状态机。

## 视频转换

Godot 不直接播放旧 MPEG-PS。使用 FFmpeg 6 或更新版本转换为 Ogg Theora/Vorbis：

```powershell
.\tools\Convert-LegacyMedia.ps1 `
  -GameDirectory E:\1937\1937tzb_1229 `
  -FfmpegExecutable E:\tools\ffmpeg\bin\ffmpeg.exe
```

默认只转换原程序引用的 `logo` 和 `historical_intro`。要明确转换未引用的三个附带视频：

```powershell
.\tools\Convert-LegacyMedia.ps1 `
  -GameDirectory E:\1937\1937tzb_1229 `
  -FfmpegExecutable E:\tools\ffmpeg\bin\ffmpeg.exe `
  -IncludeUnreferencedBonusVideos
```

输出位于 `LocalAssets/converted/media/video/*.ogv`，并生成带源/输出 SHA-256 的本地 `media-transcode-manifest.json`。这些文件被 Git 忽略。脚本已用完整 10 秒 logo 实测，Theora 视频可生成；历史片采用 30 FPS 并按原播放方式恢复为 640×480。

## 验证

- C# 合成测试验证简报、示意图、结局、角色/事件分类、variant 顺序和 bonus 安全标记，不读取原资源。
- `media_runtime_test.gd` 在完全没有 `LocalAssets` 时验证元数据、对白 schema、简报文字降级、音视频缺失返回/信号、Music/Voice/SFX 分流、角色语音按需并发与槽位复用、8 路预热 SFX 的确定性空闲选择与第 9 路非抢占扩展、影片音轨总线、Esc 松开语义、对白自动前进只等待专用对白播放器，以及简报—对白—结局连续切换、外部预暂停和离树清理时的暂停恢复。
- 本地存在生成目录时，`real_media_test.gd` 审计十二张简报、十二张示意图、128 个 WAV 的存在与 Godot 解码，以及 `126 SLF + 2 GFL-only` 来源闭环；若已转码 logo，还会实际启动 Theora 播放器。套件在日志中输出当前检查数，文档不固定复制易过期计数。
- `Check-NoOriginalAssets.ps1` 继续禁止 WAV、SVT、VWF、GFL 和生成资产进入提交。

## 仍需人工恢复的边界

可以自动恢复的是媒体身份、逐关简报/示意图、声音语义类别、角色声线和可重复播放接口。无法从当前文件自动证明的是逐场剧情对白原文、说话时机、镜头运动、角色站位和任务中途过场触发顺序；这些信息必须通过原版实机录像/逐关操作核对后写入对白与镜头数据，不能仅凭文件体积或名称猜测。

## 原版角色语音选择器

对 `sub_45D610`、`sub_45D7B0`、`sub_45D900`、`sub_45DA60` 的离线调用链复核纠正了早期 SDK 中的误标：它们并非角色动画选择器，而是最终调用 `sub_40B800`、按 `1937Sound.slf` 顺序索引播放对象的语音选择器。

`scripts/legacy_actor_audio_rules.gd` 现已固定四组规则：玩家被选中、玩家接受命令、敌方首次喝止、敌方后续追喊。规则覆盖 34 个“语音族 × runtime actor type”组合、17 个唯一的 MSVCRT `rand()` 调用点，并保留 SLF 序号与非线性的 GFL 索引映射。偶数随机值选择表中第一项，奇数选择第二项；固定语音不消费随机流。玩家选择、地面移动确认和敌方两组喝止都已接入进程级共享 CRT 流并按精确 GFL 索引播放，关卡加载时也按索引静默预解码，不改变播放或随机状态。

敌方语音的触发条件来自 `sub_45C710` 而非文件名推测：`sub_45C390` 首次返回可见活目标、角色进入 contact state 1 后调用 `sub_45D900`；后续反应计数到期时先抽取 `0x45CD01` 的下一个上限，只有 `sub_4569A0` 仍无法开始攻击才调用 `sub_45DA60` 并继续追击。`legacy_actor_audio_test.gd` 在不读取任何原版媒体的情况下验证全部规则、SLF/GFL 顺序、17 个调用点语义、首次/后续状态以及共享随机顺序。

声音重叠规则也来自离线反汇编，而不是主观调音：`sub_40B800` 找到指定声音对象后调用 `sub_40B080`，后者只递增对象内 `+0x128` 的本帧请求数；逐帧更新 `sub_40B840` 对每个声音对象调用 `sub_40B090` 后再把请求数清零。`sub_40AFB0` 会按请求数增减该声音对象自己的 DirectSound 缓冲区，`sub_40B090` 随后通过 `sub_40C670` 跳过仍在播放的缓冲区，并以 `sub_40C320` 启动空闲缓冲区。由此可知原版不存在会截断其他角色的全局语音优先级：不同声音资源天然并发，同一资源在同一帧被请求多次时也可复制缓冲区并发。Remake 因而把模态对白与战场角色语音分开；后者在全部现有槽都忙时新增播放器，而不是抢占正在播放的声音，关卡切换时再统一停止并清理索引。
