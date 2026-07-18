using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class VwfNavigationGridSyntheticTests
{
    public static int Run()
    {
        var checks = 0;
        var layers = new Dictionary<VwfSemanticLayer, IReadOnlyList<uint>>
        {
            [VwfSemanticLayer.LineOfSightObstacle] = new uint[] { 0, 1, 0, 1012, 0, 0 },
            [VwfSemanticLayer.MovementObstacle] = new uint[] { 0, 1, 1012, 1013, 0, 0 },
            [VwfSemanticLayer.Event] = new uint[] { 0, 0, 0, 0, 7, 0 },
            [VwfSemanticLayer.ManualMovementCorrection] = new uint[] { 0, 1, 0, 0, 0, 0 }
        };
        var grid = VwfNavigationGrid.Create(3, 2, 32, 16, layers);

        Equal(3u, grid.Width, "navigation width", ref checks);
        Equal(2u, grid.Height, "navigation height", ref checks);
        Equal(32u, grid.CellWidth, "navigation cell width", ref checks);
        Equal(16u, grid.CellHeight, "navigation cell height", ref checks);
        Equal(1012u, grid.GetValue(VwfSemanticLayer.MovementObstacle, 2, 0), "movement occupant", ref checks);
        Equal(true, grid.IsBlocked(VwfSemanticLayer.MovementObstacle, 2, 0), "occupied cell blocks", ref checks);
        Equal(false, grid.IsBlocked(VwfSemanticLayer.MovementObstacle, 2, 0, 12), "own scene can be ignored", ref checks);
        Equal(12, VwfNavigationGrid.OccupyingSceneIndex(1012), "scene index decoding", ref checks);
        Equal<int?>(null, VwfNavigationGrid.OccupyingSceneIndex(1), "static obstacle is not a scene", ref checks);

        using var serialized = new MemoryStream();
        grid.Write(serialized);
        Equal(
            VwfNavigationGrid.HeaderSize +
                (VwfNavigationGrid.SemanticLayerCount * (4 + (grid.CellCount * 4))),
            checked((int)serialized.Length),
            "navigation binary length",
            ref checks);
        serialized.Position = 0;
        var roundTrip = VwfNavigationGrid.Read(serialized);
        Equal(
            1013u,
            roundTrip.GetValue(VwfSemanticLayer.MovementObstacle, 0, 1),
            "navigation binary round trip",
            ref checks);
        Equal(
            7u,
            roundTrip.GetValue(VwfSemanticLayer.Event, 1, 1),
            "event layer round trip",
            ref checks);

        var truncatedBytes = serialized.ToArray()[..^1];
        Throws<InvalidDataException>(
            () => VwfNavigationGrid.Read(new MemoryStream(truncatedBytes)),
            "truncated navigation rejection",
            ref checks);
        var trailingBytes = serialized.ToArray().Concat(new byte[] { 1 }).ToArray();
        Throws<InvalidDataException>(
            () => VwfNavigationGrid.Read(new MemoryStream(trailingBytes)),
            "trailing navigation rejection",
            ref checks);

        return checks;
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

    private static void Throws<TException>(Action action, string description, ref int checks)
        where TException : Exception
    {
        checks++;
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException($"{description}: expected {typeof(TException).Name}.");
    }
}
