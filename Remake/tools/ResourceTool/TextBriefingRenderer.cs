using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Text.Json;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceTool;

internal sealed record GeneratedTextBriefing(
    int Number,
    string ResourceName,
    string Title,
    byte[] IBlock,
    byte[] Png);

internal static class TextBriefingRenderer
{
    private const int Width = 640;
    private const int Height = 480;

    public static IReadOnlyList<GeneratedTextBriefing> RenderCatalog(
        string catalogPath)
    {
        using var document = JsonDocument.Parse(
            File.ReadAllText(Path.GetFullPath(catalogPath)));
        if (!document.RootElement.TryGetProperty(
                "missions",
                out var missions) ||
            missions.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                "The briefing catalog must contain a missions array.");
        }

        var generated = new List<GeneratedTextBriefing>();
        foreach (var mission in missions.EnumerateArray())
        {
            var number = mission.GetProperty("number").GetInt32();
            var title = mission.GetProperty("title").GetString() ?? "";
            var briefing =
                mission.GetProperty("briefing").GetString() ?? "";
            var objectives = mission.GetProperty("objectives")
                .EnumerateArray()
                .Select(value => value.GetString() ?? "")
                .ToArray();
            if (number is < 1 or > 15 ||
                string.IsNullOrWhiteSpace(title) ||
                string.IsNullOrWhiteSpace(briefing) ||
                objectives.Length != 3 ||
                objectives.Any(string.IsNullOrWhiteSpace))
            {
                throw new InvalidDataException(
                    $"Mission {number} has incomplete briefing text.");
            }

            using var bitmap = Render(
                number,
                title,
                briefing,
                objectives);
            var rgb565 = ToRgb565(bitmap);
            var iblock = IBlockImageEncoder.EncodeRgb565(
                Width,
                Height,
                rgb565);
            using var pngStream = new MemoryStream();
            bitmap.Save(pngStream, ImageFormat.Png);
            generated.Add(new GeneratedTextBriefing(
                number,
                number <= 12
                    ? $"Intro_{number - 1:D3}.psd"
                    : $"Brief_{number - 1:D3}.psd",
                title,
                iblock,
                pngStream.ToArray()));
        }

        if (generated.Count != 15 ||
            generated.Select(item => item.Number).Distinct().Count() !=
            15 ||
            generated.Min(item => item.Number) != 1 ||
            generated.Max(item => item.Number) != 15)
        {
            throw new InvalidDataException(
                "The text briefing catalog must define levels 1 through 15.");
        }
        return generated
            .OrderBy(item => item.Number)
            .ToArray();
    }

    public static void WritePreviewDirectory(
        IReadOnlyList<GeneratedTextBriefing> briefings,
        string outputDirectory,
        bool includeIBlock)
    {
        var root = Path.GetFullPath(outputDirectory);
        Directory.CreateDirectory(root);
        foreach (var briefing in briefings)
        {
            File.WriteAllBytes(
                Path.Combine(
                    root,
                    $"mission-{briefing.Number:D2}.png"),
                briefing.Png);
            if (includeIBlock)
            {
                File.WriteAllBytes(
                    Path.Combine(
                        root,
                        briefing.ResourceName + ".iblock"),
                    briefing.IBlock);
            }
        }
    }

    private static Bitmap Render(
        int number,
        string title,
        string briefing,
        IReadOnlyList<string> objectives)
    {
        var bitmap = new Bitmap(
            Width,
            Height,
            PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.TextRenderingHint =
            TextRenderingHint.ClearTypeGridFit;
        using var background = new LinearGradientBrush(
            new Rectangle(0, 0, Width, Height),
            Color.FromArgb(17, 23, 28),
            Color.FromArgb(32, 36, 38),
            LinearGradientMode.ForwardDiagonal);
        graphics.FillRectangle(
            background,
            0,
            0,
            Width,
            Height);

        DrawDeterministicTexture(graphics, number);
        using var outerPen = new Pen(
            Color.FromArgb(155, 151, 125),
            2);
        using var innerPen = new Pen(
            Color.FromArgb(72, 117, 104),
            1);
        graphics.DrawRectangle(outerPen, 8, 8, 623, 463);
        graphics.DrawRectangle(innerPen, 14, 14, 611, 451);

        using var chapterFont = CreateFont(12, FontStyle.Bold);
        using var titleFont = CreateFont(24, FontStyle.Bold);
        using var labelFont = CreateFont(12, FontStyle.Bold);
        using var bodyFont = CreateFont(12, FontStyle.Regular);
        using var objectiveFont = CreateFont(11, FontStyle.Regular);
        using var footerFont = CreateFont(9, FontStyle.Regular);
        using var white = new SolidBrush(Color.FromArgb(236, 238, 228));
        using var muted = new SolidBrush(Color.FromArgb(171, 184, 173));
        using var accent = new SolidBrush(Color.FromArgb(224, 77, 62));
        using var panel = new SolidBrush(Color.FromArgb(148, 8, 12, 15));
        using var divider = new Pen(Color.FromArgb(92, 128, 115));

        graphics.DrawString(
            $"任务 {number:D2}",
            chapterFont,
            muted,
            new RectangleF(26, 23, 130, 28));
        graphics.DrawString(
            title,
            titleFont,
            white,
            new RectangleF(160, 18, 450, 45),
            SingleLineFormat());
        graphics.DrawLine(divider, 26, 68, 612, 68);

        graphics.FillRectangle(panel, 26, 82, 372, 332);
        graphics.FillRectangle(panel, 410, 82, 202, 332);
        graphics.DrawString(
            "任务简报",
            labelFont,
            accent,
            new RectangleF(40, 96, 130, 28));
        graphics.DrawString(
            briefing,
            bodyFont,
            white,
            new RectangleF(40, 128, 344, 270),
            ParagraphFormat());

        graphics.DrawString(
            "行动目标",
            labelFont,
            accent,
            new RectangleF(424, 96, 150, 28));
        var objectiveTop = 133f;
        for (var index = 0; index < objectives.Count; index++)
        {
            graphics.FillEllipse(
                accent,
                425,
                objectiveTop + 5,
                8,
                8);
            graphics.DrawString(
                objectives[index],
                objectiveFont,
                white,
                new RectangleF(
                    440,
                    objectiveTop,
                    157,
                    78),
                ParagraphFormat());
            objectiveTop += 88;
        }

        graphics.DrawLine(divider, 26, 428, 612, 428);
        graphics.DrawString(
            "单击鼠标或按 Enter 继续",
            footerFont,
            muted,
            new RectangleF(26, 442, 586, 20),
            CenterFormat());
        return bitmap;
    }

    private static void DrawDeterministicTexture(
        Graphics graphics,
        int number)
    {
        var random = new Random(1937 + number);
        using var pen = new Pen(
            Color.FromArgb(22, 208, 214, 194),
            1);
        for (var index = 0; index < 80; index++)
        {
            var x = random.Next(0, Width);
            var y = random.Next(0, Height);
            graphics.DrawLine(
                pen,
                x,
                y,
                Math.Min(Width - 1, x + random.Next(8, 72)),
                Math.Min(Height - 1, y + random.Next(-10, 11)));
        }
    }

    private static Font CreateFont(
        float size,
        FontStyle style)
    {
        foreach (var name in new[]
                 {
                     "Microsoft YaHei UI",
                     "Microsoft YaHei",
                     "SimHei",
                     FontFamily.GenericSansSerif.Name
                 })
        {
            try
            {
                var font = new Font(
                    name,
                    size,
                    style,
                    GraphicsUnit.Point);
                if (font.Name.Equals(
                        name,
                        StringComparison.OrdinalIgnoreCase) ||
                    name == FontFamily.GenericSansSerif.Name)
                {
                    return font;
                }
                font.Dispose();
            }
            catch (ArgumentException)
            {
                // Try the next installed CJK-capable family.
            }
        }
        throw new InvalidDataException(
            "No usable font is installed for text briefing rendering.");
    }

    private static byte[] ToRgb565(Bitmap bitmap)
    {
        var rectangle = new Rectangle(
            0,
            0,
            bitmap.Width,
            bitmap.Height);
        var locked = bitmap.LockBits(
            rectangle,
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb);
        try
        {
            var output = new byte[
                checked(bitmap.Width * bitmap.Height * 2)];
            var row = new byte[Math.Abs(locked.Stride)];
            for (var y = 0; y < bitmap.Height; y++)
            {
                var sourceY = locked.Stride >= 0
                    ? y
                    : bitmap.Height - 1 - y;
                Marshal.Copy(
                    locked.Scan0 + sourceY * locked.Stride,
                    row,
                    0,
                    row.Length);
                for (var x = 0; x < bitmap.Width; x++)
                {
                    var source = x * 4;
                    var blue = row[source];
                    var green = row[source + 1];
                    var red = row[source + 2];
                    var pixel = (ushort)(
                        ((red >> 3) << 11) |
                        ((green >> 2) << 5) |
                        (blue >> 3));
                    var target = (y * bitmap.Width + x) * 2;
                    output[target] = unchecked((byte)pixel);
                    output[target + 1] =
                        unchecked((byte)(pixel >> 8));
                }
            }
            return output;
        }
        finally
        {
            bitmap.UnlockBits(locked);
        }
    }

    private static StringFormat ParagraphFormat() =>
        new()
        {
            Alignment = StringAlignment.Near,
            LineAlignment = StringAlignment.Near,
            Trimming = StringTrimming.EllipsisCharacter,
            FormatFlags = StringFormatFlags.LineLimit
        };

    private static StringFormat SingleLineFormat() =>
        new()
        {
            Alignment = StringAlignment.Near,
            LineAlignment = StringAlignment.Center,
            Trimming = StringTrimming.EllipsisCharacter,
            FormatFlags = StringFormatFlags.NoWrap
        };

    private static StringFormat CenterFormat() =>
        new()
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
            Trimming = StringTrimming.EllipsisCharacter,
            FormatFlags = StringFormatFlags.NoWrap
        };
}
