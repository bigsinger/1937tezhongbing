namespace Mission1937.Remake.Resources;

/// <summary>
/// A decoded Intuition Engine sprite serial identifier.
/// </summary>
public sealed record SprAnimationSemantic(
    int SerialId,
    int ActionIndex,
    string ActionKey,
    string ActionName,
    int DirectionIndex,
    string DirectionKey,
    string DirectionName,
    bool IsReserved);

/// <summary>
/// Decodes the action/direction identifier stored in SPR group parameter 0.
/// The two source lookup tables live at M1937.exe VA 0x4CFA2C and 0x4CFA7C.
/// </summary>
public static class SprAnimationSemantics
{
    public const int DirectionStride = 9;

    private static readonly Definition[] Actions =
    [
        new("none", "无"),
        new("stand", "站立"),
        new("stand_action", "站立动作"),
        new("walk", "行走"),
        new("run", "跑"),
        new("death", "死亡"),
        new("pistol_attack", "手枪攻击"),
        new("crawl", "匍匐前进"),
        new("active_action", "主动动作"),
        new("rifle_attack", "步枪攻击"),
        new("machine_gun_attack", "机关枪攻击"),
        new("grenade_attack", "手榴弹攻击"),
        new("broadsword_attack", "大刀攻击"),
        new("dagger_attack", "匕首攻击"),
        new("dart_attack", "飞镖攻击"),
        new("slingshot_attack", "弹弓攻击"),
        new("reserved_1", "保留序列1", true),
        new("reserved_2", "保留序列2", true),
        new("reserved_3", "保留序列3", true),
        new("reserved_4", "保留序列4", true)
    ];

    private static readonly Definition[] Directions =
    [
        new("none", "无"),
        new("north", "上"),
        new("northeast", "上右"),
        new("east", "右"),
        new("southeast", "下右"),
        new("south", "下"),
        new("southwest", "下左"),
        new("west", "左"),
        new("northwest", "左上")
    ];

    public static int MaximumSerialId => checked((Actions.Length * DirectionStride) - 1);

    public static SprAnimationSemantic Decode(int serialId)
    {
        if (serialId < 0 || serialId > MaximumSerialId)
        {
            throw new ArgumentOutOfRangeException(
                nameof(serialId),
                serialId,
                $"SPR serial identifiers must be between 0 and {MaximumSerialId}.");
        }

        var actionIndex = serialId / DirectionStride;
        var directionIndex = serialId % DirectionStride;
        var action = Actions[actionIndex];
        var direction = Directions[directionIndex];
        return new SprAnimationSemantic(
            serialId,
            actionIndex,
            action.Key,
            action.Name,
            directionIndex,
            direction.Key,
            direction.Name,
            action.IsReserved);
    }

    private sealed record Definition(string Key, string Name, bool IsReserved = false);
}
