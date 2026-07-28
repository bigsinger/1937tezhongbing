// Generated from SDK/mission-routes.json. Do not edit.
namespace Mission1937.SDK.Generated
{
    public sealed class M1937MissionRoute
    {
        public M1937MissionRoute(int selectorLevel, int engineMission, string id, string vwfName, bool requiresFile, long redirectRva, string redirectExpected, string title, string briefing, string[] objectives, bool replaceLegacyBriefing)
        {
            SelectorLevel = selectorLevel;
            EngineMission = engineMission;
            Id = id;
            VwfName = vwfName;
            RequiresFile = requiresFile;
            RedirectRva = redirectRva;
            RedirectExpected = redirectExpected;
            Title = title;
            Briefing = briefing;
            Objectives = objectives;
            ReplaceLegacyBriefing = replaceLegacyBriefing;
        }
        public int SelectorLevel { get; private set; }
        public int EngineMission { get; private set; }
        public string Id { get; private set; }
        public string VwfName { get; private set; }
        public bool RequiresFile { get; private set; }
        public long RedirectRva { get; private set; }
        public string RedirectExpected { get; private set; }
        public string Title { get; private set; }
        public string Briefing { get; private set; }
        public string[] Objectives { get; private set; }
        public bool ReplaceLegacyBriefing { get; private set; }
    }

    public static class M1937MissionRoutes
    {
        public static readonly M1937MissionRoute[] All =
        {
            new M1937MissionRoute(1, 1, "m000", "1937M000.VWF", true, 0L, "", "营救行动", "日军扫荡后，村庄被岗哨、田地和围墙切成数个警戒区。掌握敌军布防的彭鑫与一直帮助乡亲转移粮食、伤员的老罗叔都被困在村中。强子必须利用庄稼和建筑隐蔽接近，救出两人，并把所有幸存者安全带到撤离点。", new[] { "找到并救出彭鑫。", "找到并救出老罗叔。", "保护获救人员和队员一同抵达撤离点。" }, true),
            new M1937MissionRoute(2, 2, "m001", "1937M001.VWF", true, 0L, "", "奇袭火车站", "敌军把火车站作为兵员和物资集散地，并扣押了铁蛋爹。古明需要先取得军服，利用伪装穿过部分警戒区；救出人质后再摧毁两个兵营，并赶在列车离站前完成撤离。", new[] { "取得军服并利用伪装进入站区。", "救出铁蛋爹，摧毁两个敌军兵营。", "让古明与铁蛋爹在时限内登上指定列车。" }, true),
            new M1937MissionRoute(3, 3, "m002", "1937M002.VWF", true, 0L, "", "劫狱", "强子在行动中被捕，敌军企图从他身上追查地下交通线。老赵必须在监区封锁前潜入救人，再炸毁装载军需品的卡车以打乱追捕计划，最后与强子共同撤离。", new[] { "潜入监区并救出强子。", "炸毁敌军军需卡车。", "确保强子与老赵一同抵达撤离区。" }, true),
            new M1937MissionRoute(4, 4, "m003", "1937M003.VWF", true, 0L, "", "铁路桥", "敌军准备通过铁路桥向前线输送增援。桥体庞大，单点爆破无法阻断通行；小队必须沿桥区在五个关键位置布置炸药，同时保存最后撤离所需的通道和弹药。", new[] { "在铁路桥五个关键位置全部布置炸药。", "避免队员掉队并保留安全撤离路线。", "完成布置后让全体人员登上撤离卡车。" }, true),
            new M1937MissionRoute(5, 5, "m004", "1937M004.VWF", true, 0L, "", "火烧粮仓", "敌军掠夺当地粮食并集中囤放，准备长期控制周边村镇。古明在侦察中被困，一名军官还携带后续调运计划。老赵要先救人、取得计划书，再烧毁两座粮仓。", new[] { "找到并救出古明。", "处置指定军官并拾取其携带的计划书。", "烧毁两座敌军粮仓。" }, true),
            new M1937MissionRoute(6, 6, "m005", "1937M005.VWF", true, 0L, "", "大闹寒江镇", "叛徒阿贵向敌军出卖地下人员，并携带一份可能暴露联络网的文件躲进寒江镇。镇内巷道狭窄、岗哨密集，小队必须确认目标、夺回文件，并尽量避免把无辜居民卷入交火。", new[] { "在寒江镇内找到叛徒阿贵。", "处置阿贵并取得其携带的文件。", "保存队伍力量，安全离开镇区。" }, true),
            new M1937MissionRoute(7, 7, "m006", "1937M006.VWF", true, 0L, "", "惩罚", "孙大麻子即将与日军人员加藤孝一接头。小队不能过早惊动目标，必须保持距离尾随，确认完整交易链条；接头事实成立后，再同时处置两名目标并迅速撤离。", new[] { "秘密尾随孙大麻子并确认接头地点。", "处置孙大麻子与加藤孝一。", "避开敌军封锁并从指定区域撤离。" }, true),
            new M1937MissionRoute(8, 8, "m007", "1937M007.VWF", true, 0L, "", "脱困", "敌军扣押了铁蛋的父母和孙小姐，企图以人质逼迫群众交出武工队线索。铁蛋与队友必须在包围收紧前依次救出三人，并保护不断扩大的护送队伍一同脱困。", new[] { "救出铁蛋的父亲和母亲。", "救出孙小姐并保护所有人质。", "在时限内让全体人员一同进入撤离区。" }, true),
            new M1937MissionRoute(9, 9, "m008", "1937M008.VWF", true, 0L, "", "暗战矿坑", "矿坑被敌军改造成工事和物资据点。老赵和大牛必须在四处工事入口分别布置炸药；任何提前引爆都会惊动全部守军并可能封死退路，必须等全部位置确认后统一行动。", new[] { "在四处矿坑工事入口全部布置炸药。", "所有炸药就位后再统一手动引爆。", "爆破完成后让老赵和大牛乘升降机撤离。" }, true),
            new M1937MissionRoute(10, 10, "m009", "1937M009.VWF", true, 0L, "", "夺宝奇兵", "一列军火列车即将完成物资交接，两名军官分别携带运输文件。小队需要同时处理情报、守军和列车三条任务线：夺取两份文件，解除敌军组织抵抗的能力，并在列车关键位置完成爆破。", new[] { "从两名军官处取得两份交接文件。", "清除仍能组织抵抗的日军。", "在军火列车四个关键位置完成爆破。" }, true),
            new M1937MissionRoute(11, 11, "m010", "1937M010.VWF", true, 0L, "", "血色渡口", "敌军占据渡口四处制高点，封锁河道和岸上通路。老赵、强子、大牛和古明必须分队同步推进，并在限定时间内分别进入指定高地、同时保持占领，才能真正打开渡口。", new[] { "让老赵、强子、大牛和古明分别接近指定高地。", "在限定时间内同时占领四处高地。", "保持四名指定队员生还，完成渡口控制。" }, true),
            new M1937MissionRoute(12, 12, "m011", "1937M011.VWF", true, 0L, "", "破袭机场", "此前取得的情报指向一座军用机场。敌军空军指挥官正在组织新的行动，飞机、指挥设施和油料目标分散在机场各区。小队必须彻底破坏基地的恢复能力，并活着走出封锁区。", new[] { "刺杀敌军空军指挥官。", "炸毁机场内六处指定目标。", "完成破袭后从西北方向撤离。" }, true),
            new M1937MissionRoute(13, 12, "m012", "1937M012.VWF", true, 0x000CF4A8L, "1937M011.VWF", "余烬行动", "1937 年冬，敌军在遭破袭的野战机场上恢复了临时补给线，并把六处油料、通信和弹药节点分散在机场各区。强子与老赵从西南排水沟潜入，必须依次破坏六处节点，在增援合围前穿越纵深，从西北撤离点脱身。", new[] { "破坏机场内六处油料、通信和弹药补给节点。", "可选：处置日军空军指挥官。", "确保强子与老赵生还，并从西北排水口撤离。" }, true),
            new M1937MissionRoute(14, 7, "m013", "1937M013.VWF", true, 0x000CF4F8L, "1937M006.VWF", "锄奸行动", "1944 年，鲁西敌后根据地外缘的平安镇出现了一条向日军特务机关输送地下交通员名单的暗线。武工队员强子奉命从镇西侧暗巷潜入，必须先尾随汉奸孙大麻子确认接头事实，再分别处置孙大麻子与化名王老板的日军特务加藤，取得名单后从东侧秘密交通口撤离。", new[] { "靠近接头点，确认孙大麻子的叛变事实。", "处置孙大麻子与日军特务加藤。", "取得名单并从镇东秘密交通口撤离。" }, true),
            new M1937MissionRoute(15, 7, "m014", "1937M014.VWF", true, 0x000CF4F8L, "1937M006.VWF", "破晓密令（拓扑安全合成地图）", "1944 年秋，平汉铁路东侧的青石镇成为日伪军封锁根据地交通线的临时中转站。武工队员强子从镇西暗巷潜入，先与晨市交通员接头，确认两名掌握封锁计划的关键人物；随后分别截获二人携带的口令和布防图，最后从镇东交通口撤离。", new[] { "在晨市与交通员接头。", "截获伪警备队口令与日军封锁布防图。", "携带情报从镇东秘密交通口撤离。" }, true),
        };

        public static M1937MissionRoute Find(int selectorLevel)
        {
            foreach (M1937MissionRoute route in All)
            {
                if (route.SelectorLevel == selectorLevel)
                    return route;
            }
            return null;
        }
    }
}
