using System.Text;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class VwfSceneListSyntheticTests
{
    public static int Run(string directory)
    {
        var checks = 0;
        var databasePath = System.IO.Path.Combine(directory, "scene-list-synthetic.dbl");
        var worldPath = System.IO.Path.Combine(directory, "scene-list-synthetic.vwf");
        CreateDatabase(databasePath);
        CreateWorld(worldPath);

        var database = DblDatabase.Open(databasePath);
        Equal(2, database.Entries.Count, "DBL entry count", ref checks);
        Equal("角色.spr", database.Entries[1].ResourceName, "DBL shifted GBK resource name", ref checks);
        Equal("角色", database.Entries[1].CategoryName, "DBL category mapping", ref checks);
        Equal(14, database.Entries[1].HeaderValues.Count, "DBL sprite header value count", ref checks);
        Equal(108u, database.Entries[1].HeaderValues[8], "DBL raw sprite h8", ref checks);
        Equal<uint?>(108u, database.Entries[1].FactionId, "DBL sprite faction h8", ref checks);
        Equal<uint?>(108u, database.Entries[1].TeamId, "DBL sprite team h8 alias", ref checks);
        Equal<uint?>(112u, database.Entries[1].SpecialSensor, "DBL sprite special sensor h12", ref checks);
        Equal(
            102,
            OriginalWorldPickupEvidence.RuntimeItemId(database.Entries[1]),
            "DBL sprite runtime item header h2",
            ref checks);
        Equal(
            new OriginalInventoryDestination("weapon", 2),
            OriginalWorldPickupEvidence.ClassifyItem(38),
            "original firearm container routing",
            ref checks);
        Equal(
            new OriginalInventoryDestination("weapon", 0),
            OriginalWorldPickupEvidence.ClassifyItem(45),
            "original explosive container routing",
            ref checks);
        Equal(
            new OriginalInventoryDestination("backpack", 0),
            OriginalWorldPickupEvidence.ClassifyItem(46),
            "original backpack container routing",
            ref checks);
        Equal(0, database.Entries[0].HeaderValues.Count, "DBL tile group has no sprite header", ref checks);
        Equal(1, database.TileGroupMap.Count, "DBL tile-group map count", ref checks);
        Equal(0, database.ResolveTileGroupMapId(1)?.Id, "DBL one-based tile-group map ID", ref checks);
        Equal<DblEntry?>(null, database.ResolveTileGroupMapId(0), "DBL tile-group zero sentinel", ref checks);

        var terrain = VwfTerrainGrid.Open(worldPath, database);
        Equal(5, terrain.Layers.Count, "VWF terrain layer count", ref checks);
        Equal(351L, terrain.SceneListOffset, "VWF terrain-to-SLIST1 boundary", ref checks);
        var cell = terrain.GetCell(0, 0);
        Equal((ushort)3, cell.TileIndex, "VWF terrain tile index", ref checks);
        Equal((ushort)1, cell.TileGroupMapId, "VWF terrain tile-group map ID", ref checks);
        Equal(0x11223344u, cell.Layer2, "VWF terrain second raw layer", ref checks);
        Equal("地形.tlg", terrain.ResolveTileGroup(cell)?.ResourceName, "VWF terrain DBL mapping", ref checks);

        var scene = VwfSceneList.Open(worldPath, database);
        Equal(2, scene.SlotCount, "SLIST1 slot count", ref checks);
        Equal(1, scene.EmptySlotCount, "SLIST1 empty slot count", ref checks);
        Equal(1, scene.Entities.Count, "SLIST1 entity count", ref checks);
        var entity = scene.Entities[0];
        Equal(1, entity.SceneIndex, "SLIST1 retained slot index", ref checks);
        Equal(1, entity.DatabaseEntryId, "SLIST1 DBL identifier", ref checks);
        Equal("角色.spr", entity.DatabaseEntry?.ResourceName, "SLIST1 DBL resource mapping", ref checks);
        Equal(6u, entity.DirectionIndex, "SLIST1 direction at prefix +44", ref checks);
        Equal(2u, entity.DeathState, "SLIST1 death state at prefix +48", ref checks);
        Equal(1u, entity.CrawlState, "SLIST1 crawl state at prefix +56", ref checks);
        Equal(320, entity.WorldX, "SLIST1 world X", ref checks);
        Equal(168, entity.WorldY, "SLIST1 world Y", ref checks);
        Equal(2, entity.Patrol?.Waypoints.Count ?? -1, "SLIST1 patrol waypoint count", ref checks);
        Equal(1u, entity.Patrol?.CurrentWaypointIndex ?? uint.MaxValue, "SLIST1 current patrol waypoint", ref checks);
        Equal(1u, entity.Patrol?.PersistentFlag ?? uint.MaxValue, "SLIST1 patrol persistent flag", ref checks);
        Equal(368, entity.Patrol?.CachedWaypointWorldX ?? int.MinValue, "SLIST1 cached patrol waypoint world X", ref checks);
        Equal(168, entity.Patrol?.CachedWaypointWorldY ?? int.MinValue, "SLIST1 cached patrol waypoint world Y", ref checks);
        Equal(1u, entity.Patrol?.Enabled ?? uint.MaxValue, "SLIST1 legacy enabled alias", ref checks);
        Equal(368, entity.Patrol?.OriginX ?? int.MinValue, "SLIST1 legacy origin X alias", ref checks);
        Equal(168, entity.Patrol?.OriginY ?? int.MinValue, "SLIST1 legacy origin Y alias", ref checks);
        Equal(
            new VwfGridPoint(11, 10),
            entity.Patrol?.Waypoints[1] ?? throw new InvalidOperationException("Patrol fixture was not parsed."),
            "SLIST1 patrol waypoint",
            ref checks);
        Equal(2u, entity.AuxiliaryArrayLengths[0], "SLIST1 auxiliary array length", ref checks);
        Equal(4, entity.AuxiliaryArrays.Count, "SLIST1 auxiliary array count", ref checks);
        Equal(
            new VwfAuxiliaryEntry(50, 2, 0),
            entity.AuxiliaryArrays[0][0],
            "SLIST1 auxiliary inventory entry",
            ref checks);
        Equal(
            new VwfAuxiliaryEntry(51, 1, 1),
            entity.AuxiliaryArrays[0][1],
            "SLIST1 auxiliary second inventory entry",
            ref checks);
        Equal(1u, entity.ExtendedDataPresence, "SLIST1 extended-data presence", ref checks);
        Equal(41, entity.ExtendedFields.Count, "SLIST1 extended field count", ref checks);
        Equal(24, entity.ExtendedReservedTailFields.Count, "SLIST1 reserved tail count", ref checks);
        Equal(2u, entity.ContactState, "SLIST1 contact state ext1", ref checks);
        Equal(17u, entity.ReactionState, "SLIST1 reaction state ext23", ref checks);
        Equal(3u, entity.DefaultAttackType, "SLIST1 default attack type ext2", ref checks);
        Equal(8u, entity.CurrentHitPoints, "SLIST1 current HP ext3", ref checks);
        Equal(100u, entity.TimedActionLimit, "SLIST1 timed-action limit ext5", ref checks);
        Equal(31u, entity.TimedActionCounter, "SLIST1 timed-action counter ext6", ref checks);
        Equal(1u, entity.TimedActionProgressActive, "SLIST1 timed-action progress ext8", ref checks);
        Equal(37, entity.PursuitActorSceneIndex, "SLIST1 pursuit scene ext10", ref checks);
        Equal(4u, entity.WorldPickupQuantity, "SLIST1 pickup quantity ext11", ref checks);
        Equal(1u, entity.RouteUpdateActive, "SLIST1 route-update flag ext0", ref checks);
        Equal(1u, entity.TargetLost, "SLIST1 target-lost flag ext13", ref checks);
        Equal(1u, entity.CoordinateMoveCommandActive, "SLIST1 coordinate command ext15", ref checks);
        Equal(2u, entity.MovementPathState, "SLIST1 path state ext16", ref checks);
        Equal(1u, entity.MovementMode, "SLIST1 movement mode ext17", ref checks);
        Equal(-32, entity.ResolvedGoalX, "SLIST1 signed resolved goal X ext18", ref checks);
        Equal(0x21212121u, entity.UnknownRuntime21C, "SLIST1 unknown runtime +0x21C ext19", ref checks);
        Equal(168, entity.ResolvedGoalY, "SLIST1 resolved goal Y ext20", ref checks);
        Equal(65u, entity.SearchDelayLimit, "SLIST1 search limit ext21", ref checks);
        Equal(7u, entity.SearchDelayCounter, "SLIST1 search counter ext22", ref checks);
        Equal(3u, entity.SearchWanderStepCounter, "SLIST1 search step ext24", ref checks);
        Equal(80u, entity.PoisonCounterLimit, "SLIST1 poison limit ext27", ref checks);
        Equal(600u, entity.HypnosisCounterLimit, "SLIST1 hypnosis limit ext28", ref checks);
        Equal(0x27272727u, entity.UnknownRuntime274, "SLIST1 unknown runtime +0x274 ext30", ref checks);
        Equal(1u, entity.NavigationOccupancyEnabled, "SLIST1 navigation occupancy ext31", ref checks);
        Equal(6u, entity.StationaryRouteFacingDirection, "SLIST1 stationary facing ext32", ref checks);
        Equal(1u, entity.StationaryRouteFacingRestoreEnabled, "SLIST1 stationary-facing restore ext33", ref checks);
        Equal(100u, entity.DisguiseRecoveryLimit, "SLIST1 disguise limit ext38", ref checks);
        Equal(0xA5A5A5A5u, entity.EscortRecruitmentCompleted, "SLIST1 escort completion ext40", ref checks);
        Equal(0xA5A5A5A5u, entity.ExtendedFields[40], "SLIST1 last retained extended field", ref checks);
        Equal(0x5A5A5A5Au, entity.ExtendedReservedTailFields[0], "SLIST1 first reserved tail field", ref checks);
        Equal(0xC3C3C3C3u, entity.ExtendedReservedTailFields[23], "SLIST1 last reserved tail field", ref checks);
        Equal(
            0x25C,
            VwfActorExtendedLayoutV5.RuntimeOffsets[(int)VwfActorExtendedFieldV5.ReactionState],
            "SLIST1 reaction-state runtime offset",
            ref checks);
        Equal(
            VwfActorExtendedLayoutV5.FieldCount,
            VwfActorExtendedLayoutV5.RuntimeOffsets.Count,
            "SLIST1 runtime offset count",
            ref checks);
        Equal(
            VwfActorExtendedLayoutV5.FieldCount,
            VwfActorExtendedLayoutV5.RuntimeOffsets.Distinct().Count(),
            "SLIST1 runtime offsets are unique",
            ref checks);

        return checks;
    }

    private static void CreateDatabase(string path)
    {
        using var stream = new FileStream(path, FileMode.Create, FileAccess.Write);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        var header = new byte[DblDatabase.HeaderSize];
        Encoding.ASCII.GetBytes("DBL1 Intuition Engine Database File Version 1.0.0").CopyTo(header, 0);
        writer.Write(header);
        writer.Write(1u);
        writer.Write(2u);

        writer.Write((uint)DblEntryKind.TileGroup);
        WriteShiftedName(writer, "地形.tlg");
        WriteShiftedName(writer, "地形");
        writer.Write(0u);
        writer.Write(1u);
        writer.Write(1u);
        writer.Write(0u);
        writer.Write(0u);

        writer.Write((uint)DblEntryKind.Sprite);
        WriteShiftedName(writer, "角色.spr");
        WriteShiftedName(writer, "角色");
        var spriteHeader = Enumerable.Range(100, 14).Select(value => (uint)value).ToArray();
        spriteHeader[4] = 0;
        foreach (var value in spriteHeader)
        {
            writer.Write(value);
        }
        writer.Write(new byte[164]);

        writer.Write(2u);
        WritePlainName(writer, "地形");
        WritePlainName(writer, "角色");
        writer.Write(0u);
        writer.Write(1u);
    }

    private static void CreateWorld(string path)
    {
        using var stream = new FileStream(path, FileMode.Create, FileAccess.Write);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        var worldPreamble = new byte[VwfTerrainGrid.PreambleSize];
        Encoding.ASCII.GetBytes("VWL1 Intuition Engine Virtual World File").CopyTo(worldPreamble, 0);
        BitConverter.GetBytes(796u).CopyTo(worldPreamble, 95);
        BitConverter.GetBytes(611u).CopyTo(worldPreamble, 99);
        BitConverter.GetBytes(1u).CopyTo(worldPreamble, 135);
        BitConverter.GetBytes(1u).CopyTo(worldPreamble, 139);
        BitConverter.GetBytes(64u).CopyTo(worldPreamble, 143);
        writer.Write(worldPreamble);

        uint[] layerValues = [0x00010003u, 0x11223344u, 1u, 0u, 1u];
        for (var layerIndex = 0; layerIndex < VwfTerrainGrid.LayerCount; layerIndex++)
        {
            writer.Write(checked((uint)(layerIndex + 1)));
            writer.Write(1u);
            writer.Write(1u);
            writer.Write(1u);
            writer.Write(layerValues[layerIndex]);
        }

        writer.Write(0);
        writer.Write(0);
        writer.Write(796);
        writer.Write(611);

        var sceneHeader = new byte[VwfSceneList.HeaderSize];
        Encoding.ASCII.GetBytes("SLIST1 U.M.E Guowei 2000\0").CopyTo(sceneHeader, 0);
        BitConverter.GetBytes(2u).CopyTo(sceneHeader, 25);
        BitConverter.GetBytes(2u).CopyTo(sceneHeader, 29);
        BitConverter.GetBytes(1u).CopyTo(sceneHeader, 109);
        BitConverter.GetBytes(1u).CopyTo(sceneHeader, 113);
        BitConverter.GetBytes(64u).CopyTo(sceneHeader, 117);
        BitConverter.GetBytes(796).CopyTo(sceneHeader, 129);
        BitConverter.GetBytes(611).CopyTo(sceneHeader, 133);
        writer.Write(sceneHeader);

        writer.Write(0u);
        writer.Write(1u);
        var entityPrefix = new byte[200];
        BitConverter.GetBytes(5u).CopyTo(entityPrefix, 0);
        BitConverter.GetBytes(1).CopyTo(entityPrefix, 8);
        BitConverter.GetBytes(6u).CopyTo(entityPrefix, 44);
        BitConverter.GetBytes(2u).CopyTo(entityPrefix, 48);
        BitConverter.GetBytes(1u).CopyTo(entityPrefix, 56);
        BitConverter.GetBytes(320).CopyTo(entityPrefix, 60);
        BitConverter.GetBytes(168).CopyTo(entityPrefix, 64);
        BitConverter.GetBytes(320).CopyTo(entityPrefix, 104);
        BitConverter.GetBytes(168).CopyTo(entityPrefix, 112);
        writer.Write(entityPrefix);

        writer.Write(1u);
        writer.Write(1001u);
        writer.Write(2u);
        writer.Write(1u);
        writer.Write(new byte[2 * 8]);
        writer.Write(2u);
        writer.Write(1u);
        writer.Write(1u);
        writer.Write(368);
        writer.Write(168);
        writer.Write(10u);
        writer.Write(10u);
        writer.Write(11u);
        writer.Write(10u);

        writer.Write(1u);
        var extendedFields = new uint[41];
        extendedFields[0] = 1;
        extendedFields[1] = 2;
        extendedFields[2] = 3;
        extendedFields[3] = 8;
        extendedFields[5] = 100;
        extendedFields[6] = 31;
        extendedFields[8] = 1;
        extendedFields[10] = 37;
        extendedFields[11] = 4;
        extendedFields[13] = 1;
        extendedFields[15] = 1;
        extendedFields[16] = 2;
        extendedFields[17] = 1;
        extendedFields[18] = unchecked((uint)-32);
        extendedFields[19] = 0x21212121;
        extendedFields[20] = 168;
        extendedFields[21] = 65;
        extendedFields[22] = 7;
        extendedFields[23] = 17;
        extendedFields[24] = 3;
        extendedFields[27] = 80;
        extendedFields[28] = 600;
        extendedFields[30] = 0x27272727;
        extendedFields[31] = 1;
        extendedFields[32] = 6;
        extendedFields[33] = 1;
        extendedFields[38] = 100;
        extendedFields[40] = 0xA5A5A5A5;
        foreach (var value in extendedFields)
        {
            writer.Write(value);
        }
        writer.Write(0x5A5A5A5Au);
        writer.Write(new byte[22 * sizeof(uint)]);
        writer.Write(0xC3C3C3C3u);
        writer.Write(1u);
        writer.Write(2u);
        writer.Write(50u);
        writer.Write(51u);
        writer.Write(2u);
        writer.Write(1u);
        writer.Write(0u);
        writer.Write(1u);
        for (var arrayIndex = 1; arrayIndex < 4; arrayIndex++)
        {
            writer.Write(1u);
            writer.Write(0u);
        }
    }

    private static void WriteShiftedName(BinaryWriter writer, string value)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var field = new byte[256];
        Array.Fill(field, (byte)5);
        var encoded = Encoding.GetEncoding(936).GetBytes(value);
        for (var index = 0; index < encoded.Length; index++)
        {
            field[index] = unchecked((byte)(encoded[index] + 5));
        }

        writer.Write(field);
    }

    private static void WritePlainName(BinaryWriter writer, string value)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var field = new byte[256];
        Encoding.GetEncoding(936).GetBytes(value).CopyTo(field, 0);
        writer.Write(field);
    }

    private static void Equal<T>(T expected, T actual, string description, ref int checks)
    {
        checks++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{description}: expected '{expected}', actual '{actual}'.");
        }
    }
}
