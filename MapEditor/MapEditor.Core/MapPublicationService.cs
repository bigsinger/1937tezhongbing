using System.Security;
using System.Text;
using System.Text.Json;

namespace Mission1937.MapEditor.Core;

public sealed record MapPublicationResult(
    string OutputDirectory,
    string ReadmePath,
    string ThumbnailPath,
    string StoryPath,
    string ValidationPath,
    string ManifestPath);

public static class MapPublicationService
{
    public static MapPublicationResult Publish(
        MapDocument document,
        string outputDirectory,
        string story,
        IReadOnlyList<MapIssue> issues)
    {
        var root = Path.GetFullPath(outputDirectory);
        Directory.CreateDirectory(root);
        var thumbnail = Path.Combine(root, "thumbnail.svg");
        var storyPath = Path.Combine(root, "story.md");
        var validation = Path.Combine(root, "validation.md");
        var readme = Path.Combine(root, "README.md");
        var manifest = Path.Combine(root, "publication.json");
        AtomicWrite(thumbnail, BuildThumbnail(document));
        AtomicWrite(
            storyPath,
            $"# {document.Name}：故事章节\n\n{story.Trim()}\n");
        AtomicWrite(validation, BuildValidation(issues));
        AtomicWrite(readme, BuildReadme(document, issues));
        var payload = new
        {
            schema_version = 1,
            title = document.Name,
            generated_utc = DateTimeOffset.UtcNow,
            files = new[]
            {
                "README.md", "thumbnail.svg",
                "story.md", "validation.md"
            },
            map = new
            {
                document.Width,
                document.Height,
                object_count = document.Objects.Count,
                task_count = document.Tasks.Count
            },
            validation = new
            {
                error_count = issues.Count(item =>
                    item.Severity == MapIssueSeverity.Error),
                warning_count = issues.Count(item =>
                    item.Severity == MapIssueSeverity.Warning)
            }
        };
        AtomicWrite(
            manifest,
            JsonSerializer.Serialize(payload, new JsonSerializerOptions
            {
                WriteIndented = true
            }));
        return new MapPublicationResult(
            root, readme, thumbnail, storyPath, validation, manifest);
    }

    private static string BuildThumbnail(MapDocument document)
    {
        const int width = 800;
        const int height = 480;
        var builder = new StringBuilder();
        builder.AppendLine(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
            $"width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">");
        builder.AppendLine(
            "<rect width=\"800\" height=\"480\" fill=\"#202932\"/>");
        builder.AppendLine(
            "<rect x=\"18\" y=\"18\" width=\"764\" height=\"444\" " +
            "fill=\"#5c684c\" stroke=\"#d8cfb2\" stroke-width=\"3\"/>");
        foreach (var item in document.Objects.Take(2000))
        {
            var x = 18 + item.X / Math.Max(1.0, document.Width - 1) * 764;
            var y = 18 + item.Y / Math.Max(1.0, document.Height - 1) * 444;
            var color = item.Faction.Contains(
                "player", StringComparison.OrdinalIgnoreCase) ||
                item.Faction is "2" or "faction-2"
                ? "#53b7ff"
                : item.IsLiving ? "#d44b43" : "#e1d5aa";
            builder.AppendLine(string.Format(
                System.Globalization.CultureInfo.InvariantCulture,
                "<rect x=\"{0:F1}\" y=\"{1:F1}\" " +
                "width=\"4\" height=\"4\" fill=\"{2}\"/>",
                x - 2, y - 2, color));
        }
        builder.AppendLine(
            $"<text x=\"34\" y=\"54\" fill=\"white\" " +
            "font-family=\"Microsoft YaHei, sans-serif\" " +
            "font-size=\"24\" font-weight=\"bold\">" +
            SecurityElement.Escape(document.Name) + "</text>");
        builder.AppendLine(
            $"<text x=\"34\" y=\"84\" fill=\"#eee6d0\" " +
            "font-family=\"sans-serif\" font-size=\"14\">" +
            $"{document.Width}×{document.Height} · " +
            $"{document.Objects.Count} objects · " +
            $"{document.Tasks.Count} objectives</text>");
        builder.AppendLine("</svg>");
        return builder.ToString();
    }

    private static string BuildReadme(
        MapDocument document,
        IReadOnlyList<MapIssue> issues) =>
        $"# {document.Name}\n\n" +
        "![地图缩略图](thumbnail.svg)\n\n" +
        $"地图尺寸：{document.Width}×{document.Height}；" +
        $"对象 {document.Objects.Count} 个；任务 {document.Tasks.Count} 项。\n\n" +
        "## 内容\n\n" +
        "- [故事章节](story.md)\n" +
        "- [验证摘要](validation.md)\n\n" +
        "本目录由 1937 MapEditor 发布生成器确定性生成。\n";

    private static string BuildValidation(IReadOnlyList<MapIssue> issues)
    {
        var builder = new StringBuilder();
        builder.AppendLine("# 地图验证摘要");
        builder.AppendLine();
        builder.AppendLine(
            $"- Error：{issues.Count(item => item.Severity == MapIssueSeverity.Error)}");
        builder.AppendLine(
            $"- Warning：{issues.Count(item => item.Severity == MapIssueSeverity.Warning)}");
        builder.AppendLine(
            $"- Info：{issues.Count(item => item.Severity == MapIssueSeverity.Info)}");
        builder.AppendLine();
        builder.AppendLine("| 级别 | 代码 | 位置 | 问题 |");
        builder.AppendLine("|---|---|---|---|");
        foreach (var issue in issues)
            builder.AppendLine(
                $"| {issue.Severity} | {issue.Code} | " +
                $"{issue.Location} | {issue.Message.Replace("|", "\\|")} |");
        return builder.ToString();
    }

    private static void AtomicWrite(string path, string content)
    {
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, content, new UTF8Encoding(false));
        File.Move(temporary, path, true);
    }
}
