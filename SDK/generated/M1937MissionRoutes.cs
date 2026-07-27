// Generated from SDK/mission-routes.json. Do not edit.
namespace Mission1937.SDK.Generated
{
    public sealed class M1937MissionRoute
    {
        public M1937MissionRoute(int selectorLevel, int engineMission, string id, string vwfName, bool requiresFile, long redirectRva, string redirectExpected)
        {
            SelectorLevel = selectorLevel;
            EngineMission = engineMission;
            Id = id;
            VwfName = vwfName;
            RequiresFile = requiresFile;
            RedirectRva = redirectRva;
            RedirectExpected = redirectExpected;
        }
        public int SelectorLevel { get; private set; }
        public int EngineMission { get; private set; }
        public string Id { get; private set; }
        public string VwfName { get; private set; }
        public bool RequiresFile { get; private set; }
        public long RedirectRva { get; private set; }
        public string RedirectExpected { get; private set; }
    }

    public static class M1937MissionRoutes
    {
        public static readonly M1937MissionRoute[] All =
        {
            new M1937MissionRoute(1, 1, "m000", "1937M000.VWF", true, 0L, ""),
            new M1937MissionRoute(2, 2, "m001", "1937M001.VWF", true, 0L, ""),
            new M1937MissionRoute(3, 3, "m002", "1937M002.VWF", true, 0L, ""),
            new M1937MissionRoute(4, 4, "m003", "1937M003.VWF", true, 0L, ""),
            new M1937MissionRoute(5, 5, "m004", "1937M004.VWF", true, 0L, ""),
            new M1937MissionRoute(6, 6, "m005", "1937M005.VWF", true, 0L, ""),
            new M1937MissionRoute(7, 7, "m006", "1937M006.VWF", true, 0L, ""),
            new M1937MissionRoute(8, 8, "m007", "1937M007.VWF", true, 0L, ""),
            new M1937MissionRoute(9, 9, "m008", "1937M008.VWF", true, 0L, ""),
            new M1937MissionRoute(10, 10, "m009", "1937M009.VWF", true, 0L, ""),
            new M1937MissionRoute(11, 11, "m010", "1937M010.VWF", true, 0L, ""),
            new M1937MissionRoute(12, 12, "m011", "1937M011.VWF", true, 0L, ""),
            new M1937MissionRoute(13, 12, "m012", "1937M012.VWF", true, 0x000CF4A8L, "1937M011.VWF"),
            new M1937MissionRoute(14, 7, "m013", "1937M013.VWF", true, 0x000CF4F8L, "1937M006.VWF"),
            new M1937MissionRoute(15, 7, "m014", "1937M014.VWF", true, 0x000CF4F8L, "1937M006.VWF"),
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
