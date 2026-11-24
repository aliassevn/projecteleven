using QRCoder;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Venster "Tablet koppelen": adres, QR-code en de koppelcode van 6 cijfers.</summary>
sealed class PairWindow : Form
{
    readonly Core core;
    readonly Label help = new(), url = new(), urlMore = new(), codeTitle = new(), code = new(), expires = new(), status = new(), firewall = new();
    readonly PictureBox qr = new();
    readonly Button newCode = new();
    readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    string qrFor = "";

    static readonly Color Bg = Color.FromArgb(14, 16, 22), Fg = Color.FromArgb(220, 240, 245), Dim = Color.FromArgb(140, 160, 170), Accent = Color.FromArgb(0, 230, 205);

    public PairWindow(Core core)
    {
        this.core = core;
        Icon = TrayApp.AppIcon(32);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Bg;
        ForeColor = Fg;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(560, 330);
        Font = new Font("Segoe UI", 10f);

        qr.SetBounds(20, 20, 200, 200);
        qr.SizeMode = PictureBoxSizeMode.Zoom;
        qr.BackColor = Color.White;

        help.SetBounds(240, 20, 300, 22); help.ForeColor = Dim;
        url.SetBounds(240, 42, 300, 28); url.Font = new Font("Consolas", 13f, FontStyle.Bold); url.ForeColor = Accent;
        urlMore.SetBounds(240, 72, 300, 40); urlMore.ForeColor = Dim; urlMore.Font = new Font("Consolas", 9f);
        codeTitle.SetBounds(240, 118, 300, 22); codeTitle.ForeColor = Dim;
        code.SetBounds(240, 138, 300, 52); code.Font = new Font("Consolas", 30f, FontStyle.Bold);
        expires.SetBounds(240, 192, 300, 20); expires.ForeColor = Dim; expires.Font = new Font("Segoe UI", 9f);
        newCode.SetBounds(240, 216, 140, 30);
        newCode.FlatStyle = FlatStyle.Flat; newCode.ForeColor = Fg; newCode.FlatAppearance.BorderColor = Accent;
        newCode.Click += (_, _) => core.Pairing.Rotate();
        status.SetBounds(20, 236, 200, 22); status.ForeColor = Dim; status.Font = new Font("Segoe UI", 9f);
        firewall.SetBounds(20, 266, 520, 56); firewall.ForeColor = Dim; firewall.Font = new Font("Segoe UI", 9f);

        Controls.AddRange(new Control[] { qr, help, url, urlMore, codeTitle, code, expires, newCode, status, firewall });
        timer.Tick += (_, _) => Refresh();
        timer.Start();
        FormClosed += (_, _) => timer.Dispose();
        Refresh();
    }

    public new void Refresh()
    {
        Text = "Cyberpad — " + L("Tablet koppelen…").TrimEnd('…');
        var ips = NetUtil.LocalIPv4();
        var main = ips.Count > 0 ? $"http://{ips[0]}:{Server.Port}" : $"http://localhost:{Server.Port}";
        help.Text = L("Open op je tablet:");
        url.Text = main.Replace("http://", "");
        urlMore.Text = ips.Count > 1 ? string.Join("\n", ips.Skip(1).Take(2).Select(ip => L("of {0}", $"{ip}:{Server.Port}"))) : "";
        codeTitle.Text = L("Koppelcode");
        var c = core.Pairing.Code;
        code.Text = c.Length == 6 ? c[..3] + " " + c[3..] : c;
        var left = Math.Max(0, (int)(core.Pairing.CodeExpires - DateTime.UtcNow).TotalSeconds);
        expires.Text = L("Nieuwe code over {0}", $"{left / 60}:{left % 60:00}");
        newCode.Text = L("Nieuwe code");
        var n = core.Server.OnlineDevices.Count();
        status.Text = core.Server.Error ?? (n == 1 ? L("1 tablet verbonden") : L("{0} tablets verbonden", n));
        firewall.Text = L("Lukt het niet? Tablet en pc moeten op hetzelfde wifi-netwerk zitten, en Windows Firewall moet Cyberpad toelaten op een privénetwerk. Staat je wifi op 'Openbaar', zet het dan in Instellingen op 'Privé'.");
        if (qrFor != main)
        {
            qrFor = main;
            try
            {
                using var gen = new QRCodeGenerator();
                using var data = gen.CreateQrCode(main, QRCodeGenerator.ECCLevel.M);
                var png = new PngByteQRCode(data).GetGraphic(8);
                qr.Image?.Dispose();
                qr.Image = Image.FromStream(new MemoryStream(png));
            }
            catch { }
        }
    }
}
