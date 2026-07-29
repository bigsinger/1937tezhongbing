namespace Mission1937.Remake.Resources;

public sealed record OriginalInventoryDestination(
    string Container,
    int QuantityMode);

public sealed record OriginalWorldPickupGrant(
    int DatabaseEntryId,
    string DisplayName,
    string ResourceName,
    int ItemId,
    string Container,
    int Quantity,
    int QuantityMode);

public sealed record OriginalWorldPickupProp(
    int DatabaseEntryId,
    string DisplayName,
    string ResourceName,
    int RuntimeItemId);

public sealed record OriginalWorldPickupEvidenceReport(
    IReadOnlyList<OriginalWorldPickupGrant> PickupGrants,
    OriginalWorldPickupProp GasolineBarrel);

/// <summary>
/// Recovers field-pickup inventory routing from the stable original resource
/// database. DBL sprite header[2] is the runtime item ID. The container and
/// quantity-mode branches mirror M1937.exe sub_45AE10, while the single-item
/// grant mirrors the sub_453F70 caller.
/// </summary>
public static class OriginalWorldPickupEvidence
{
    public static readonly IReadOnlyList<int> PickupDatabaseEntryIds =
        [982, 983, 984, 986, 987, 988, 990, 993, 998, 999];

    public const int GasolineBarrelDatabaseEntryId = 1003;

    public static OriginalWorldPickupEvidenceReport Recover(
        DblDatabase database)
    {
        ArgumentNullException.ThrowIfNull(database);
        var pickups = PickupDatabaseEntryIds
            .Select(databaseEntryId =>
            {
                var entry = ResolveSprite(database, databaseEntryId);
                var itemId = RuntimeItemId(entry);
                var destination = ClassifyItem(itemId);
                return new OriginalWorldPickupGrant(
                    databaseEntryId,
                    entry.DisplayName,
                    entry.ResourceName,
                    itemId,
                    destination.Container,
                    1,
                    destination.QuantityMode);
            })
            .ToArray();
        var barrelEntry = ResolveSprite(
            database,
            GasolineBarrelDatabaseEntryId);
        var barrel = new OriginalWorldPickupProp(
            barrelEntry.Id,
            barrelEntry.DisplayName,
            barrelEntry.ResourceName,
            RuntimeItemId(barrelEntry));
        return new OriginalWorldPickupEvidenceReport(pickups, barrel);
    }

    public static int RuntimeItemId(DblEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        if (entry.Kind != DblEntryKind.Sprite ||
            entry.HeaderValues.Count != 14)
        {
            throw new InvalidDataException(
                $"DBL entry {entry.Id} is not a complete sprite record.");
        }

        return checked((int)entry.HeaderValues[2]);
    }

    public static OriginalInventoryDestination ClassifyItem(int itemId)
    {
        if (itemId is 36 or 37 or 38)
        {
            return new OriginalInventoryDestination("weapon", 2);
        }

        if (itemId is 39 or 40 or 42 or 99)
        {
            return new OriginalInventoryDestination("weapon", 1);
        }

        if (itemId is 41 or 43 or 44 or 45)
        {
            return new OriginalInventoryDestination("weapon", 0);
        }

        return new OriginalInventoryDestination("backpack", 0);
    }

    private static DblEntry ResolveSprite(
        DblDatabase database,
        int databaseEntryId)
    {
        var entry = database.Entries.FirstOrDefault(
            candidate => candidate.Id == databaseEntryId);
        if (entry is null)
        {
            throw new InvalidDataException(
                $"DBL entry {databaseEntryId} is missing.");
        }

        _ = RuntimeItemId(entry);
        return entry;
    }
}
