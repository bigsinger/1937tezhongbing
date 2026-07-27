using Mission1937.MapEditor.Core;

if (args.Length != 2)
{
    Console.Error.WriteLine(
        "Usage: AssetMetadataTool ASSET_CATALOG OUTPUT_METADATA");
    return 2;
}

try
{
    var catalog = AssetMetadataService.GenerateFromAssetCatalog(args[0]);
    AssetMetadataService.Save(catalog, args[1]);
    var loaded = AssetMetadataService.Load(args[1]);
    var errors = AssetMetadataService.CoverageErrors(args[0], loaded);
    if (errors.Count > 0)
        throw new InvalidDataException(string.Join(Environment.NewLine, errors));
    Console.WriteLine(
        $"Generated metadata for {loaded.Assets.Count} assets: {args[1]}");
    return 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine(exception.Message);
    return 1;
}
