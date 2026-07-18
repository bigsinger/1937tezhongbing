using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceFormats.Tests;

internal static class SprAnimationSemanticsTests
{
    public static int Run()
    {
        var checks = 0;

        var standNorth = SprAnimationSemantics.Decode(10);
        Equal("stand", standNorth.ActionKey, "serial 10 action", ref checks);
        Equal("north", standNorth.DirectionKey, "serial 10 direction", ref checks);

        var runSouthwest = SprAnimationSemantics.Decode(42);
        Equal("run", runSouthwest.ActionKey, "serial 42 action", ref checks);
        Equal("southwest", runSouthwest.DirectionKey, "serial 42 direction", ref checks);

        var slingshotNorthwest = SprAnimationSemantics.Decode(143);
        Equal("slingshot_attack", slingshotNorthwest.ActionKey, "serial 143 action", ref checks);
        Equal("northwest", slingshotNorthwest.DirectionKey, "serial 143 direction", ref checks);

        var reserved = SprAnimationSemantics.Decode(179);
        Equal(true, reserved.IsReserved, "reserved serial flag", ref checks);
        Equal("reserved_4", reserved.ActionKey, "reserved serial action", ref checks);

        Throws<ArgumentOutOfRangeException>(
            () => SprAnimationSemantics.Decode(-1),
            "negative serial rejection",
            ref checks);
        Throws<ArgumentOutOfRangeException>(
            () => SprAnimationSemantics.Decode(180),
            "oversized serial rejection",
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
