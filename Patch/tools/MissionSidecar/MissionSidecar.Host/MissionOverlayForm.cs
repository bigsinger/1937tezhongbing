using System.Runtime.InteropServices;

namespace Mission1937.Sidecar.Host;

internal sealed class MissionOverlayForm : Form
{
    private const int WsExTransparent = 0x00000020;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const int SwpNoActivate = 0x0010;
    private readonly MissionSession session;
    private readonly Label title = new();
    private readonly Label content = new();
    private readonly System.Windows.Forms.Timer timer = new();

    public MissionOverlayForm(MissionSession session)
    {
        this.session = session;
        Text = "1937 任务目标";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.FromArgb(25, 30, 38);
        ForeColor = Color.WhiteSmoke;
        Opacity = 0.90;
        ClientSize = new Size(350, 250);
        Padding = new Padding(16);
        Font = new Font("Microsoft YaHei UI", 9F);

        title.AutoSize = false;
        title.Dock = DockStyle.Top;
        title.Height = 32;
        title.Font = new Font(
            Font.FontFamily, 12F, FontStyle.Bold);
        title.ForeColor = Color.FromArgb(255, 211, 122);
        Controls.Add(title);

        content.AutoSize = false;
        content.Dock = DockStyle.Fill;
        content.ForeColor = Color.FromArgb(230, 234, 239);
        Controls.Add(content);

        session.ViewChanged += UpdateView;
        UpdateView(session.View);
        timer.Interval = 100;
        timer.Tick += (_, _) =>
        {
            if (session.ProcessExited)
            {
                timer.Stop();
                Close();
                return;
            }
            session.Tick();
            PositionBesideGame();
        };
        Shown += (_, _) => timer.Start();
        FormClosed += (_, _) => timer.Stop();
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |=
                WsExNoActivate | WsExToolWindow | WsExTransparent;
            return parameters;
        }
    }

    protected override void OnShown(EventArgs eventArgs)
    {
        base.OnShown(eventArgs);
        PositionBesideGame();
    }

    private void UpdateView(MissionView view)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => UpdateView(view));
            return;
        }
        title.Text = view.Title;
        var lines = new List<string>();
        foreach (var objective in view.Objectives)
        {
            var marker = objective.Completed
                ? "✓"
                : objective.Active ? "•" : "○";
            var progress = objective.RequiredCount > 1
                ? $" {objective.Count}/{objective.RequiredCount}"
                : "";
            var optional = objective.Optional ? "（可选）" : "";
            lines.Add(
                $"{marker} {objective.Title}{progress}{optional}");
        }
        lines.Add("");
        lines.Add(view.Hint);
        content.Text = string.Join(Environment.NewLine, lines);
        BackColor = view.Status switch
        {
            MissionRunStatus.Failed =>
                Color.FromArgb(62, 26, 28),
            MissionRunStatus.Succeeded =>
                Color.FromArgb(28, 57, 38),
            _ => Color.FromArgb(25, 30, 38)
        };
    }

    private void PositionBesideGame()
    {
        var handle = session.GameWindowHandle;
        if (handle == IntPtr.Zero ||
            !GetWindowRect(handle, out var rectangle))
            return;
        var x = Math.Max(
            rectangle.Left + 8,
            rectangle.Right - Width - 8);
        var y = rectangle.Top + 36;
        SetWindowPos(
            Handle,
            new IntPtr(-1),
            x,
            y,
            Width,
            Height,
            SwpNoActivate);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(
        IntPtr window,
        out Rect rectangle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        int flags);
}
