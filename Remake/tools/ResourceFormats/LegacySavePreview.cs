namespace Mission1937.Remake.Resources;

/// <summary>
/// Decodes the signature-free 320x240 IBLOCK stored beside an original SAV.
/// </summary>
public sealed class LegacySavePreview
{
    private LegacySavePreview(string path, IBlockImage image)
    {
        Path = path;
        Image = image;
    }

    public string Path { get; }

    public IBlockImage Image { get; }

    public static LegacySavePreview Open(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        var source = File.ReadAllBytes(fullPath);
        var image = IBlockImage.ReadEmbedded(source, out var consumedBytes);
        if (consumedBytes != source.Length)
        {
            throw new InvalidDataException(
                $"The legacy save preview contains {source.Length - consumedBytes} " +
                "bytes beyond its embedded IBLOCK payload.");
        }

        if (image.Width != 320 || image.Height != 240)
        {
            throw new InvalidDataException(
                $"The legacy save preview is {image.Width}x{image.Height}; expected 320x240.");
        }

        return new LegacySavePreview(fullPath, image);
    }
}
