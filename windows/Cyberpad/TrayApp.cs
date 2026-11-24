using System.Diagnostics;
using System.Reflection;
using Microsoft.Win32;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Icoon in het systeemvak (naast de klok) met het menu van Cyberpad.</summary>
sealed class TrayApp : ApplicationContext
{
    readonly Core core;
    readonly NotifyIcon icon;
    readonly ContextMenuStrip menu = new();
    PairWindow? pairWindow;
    EditorWindow? editorWindow;

    public static Icon AppIcon(int size = 32)
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico");
        return s != null ? new Icon(s, size, size) : SystemIcons.Application;
    }

    public TrayApp(Core core)
    {
        this.core = core;
        icon = new NotifyIcon { Icon = AppIcon(16), Text = "Cyberpad", Visible = true, ContextMenuStrip = menu };
        menu.Opening += (_, _) => BuildMenu();
        icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowPair(); };
        BuildMenu();
        core.UiChanged += () => Program.OnUi(() => { pairWindow?.Refresh(); icon.Text = TrayText(); });
        I18n.Changed += _ => Program.OnUi(() => editorWindow?.LanguageChanged());
    }

    string TrayText()
    {
        var n = core.Server.OnlineDevices.Count();
        var t = "Cyberpad · " + (n == 1 ? L("1 tablet verbonden") : L("{0} tablets verbonden", n));
        return t.Length > 60 ? t[..60] : t;
    }

    /// <summary>Na het starten van de server: zonder gekoppelde tablet meteen het koppelvenster tonen.</summary>
    public void ServerStarted()
    {
        if (core.Server.Error != null)
        {
            icon.ShowBalloonTip(8000, "Cyberpad", core.Server.Error, ToolTipIcon.Error);
            return;
        }
        if (core.Pairing.Devices.Count == 0) ShowPair();
        else icon.ShowBalloonTip(3000, "Cyberpad", L("Cyberpad draait. Klik op het icoon om een tablet te koppelen."), ToolTipIcon.Info);
    }

    void BuildMenu()
    {
        menu.Items.Clear();
        var status = core.Server.Error ?? L("Actief op :{0}", Server.Port);
        menu.Items.Add(new ToolStripMenuItem("Cyberpad · " + status) { Enabled = false });
        menu.Items.Add(new ToolStripMenuItem(L("Koppelcode") + ": " + Spaced(core.Pairing.Code), null, (_, _) => ShowPair()));
        menu.Items.Add(new ToolStripMenuItem(L("Tablet koppelen…"), null, (_, _) => ShowPair()));
        menu.Items.Add(new ToolStripSeparator());

        var devices = new ToolStripMenuItem(L("Gekoppelde tablets"));
        var online = core.Server.OnlineDevices.ToHashSet();
        var list = core.Pairing.Devices;
        if (list.Count == 0) devices.DropDownItems.Add(new ToolStripMenuItem(L("Nog geen tablets gekoppeld")) { Enabled = false });
        foreach (var d in list)
        {
            var item = new ToolStripMenuItem((online.Contains(d.Id) ? "● " : "○ ") + d.Name);
            var id = d.Id;
            item.DropDownItems.Add(new ToolStripMenuItem(L("Intrekken"), null, (_, _) => core.Pairing.Revoke(id)));
            devices.DropDownItems.Add(item);
        }
        menu.Items.Add(devices);
        menu.Items.Add(new ToolStripMenuItem(L("Layout bewerken…"), null, (_, _) => OpenEditor()));

        var lang = new ToolStripMenuItem(L("Taal") + " / Language");
        foreach (var (code, name) in I18n.Languages)
        {
            var c = code;
            lang.DropDownItems.Add(new ToolStripMenuItem(name, null, (_, _) => I18n.Set(c)) { Checked = I18n.Lang == code });
        }
        menu.Items.Add(lang);
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem(L("Map"), null, (_, _) => Open(Paths.Support)));
        menu.Items.Add(new ToolStripMenuItem(L("layout.json openen"), null, (_, _) => Open(core.Layouts.FilePath)));
        menu.Items.Add(new ToolStripMenuItem(L("Standaard-layout terugzetten…"), null, (_, _) => ResetLayout()));
        menu.Items.Add(new ToolStripMenuItem(L("Starten bij aanmelden"), null, (_, _) => Autostart = !Autostart) { Checked = Autostart });
        if (core.Layouts.LastError is { } err) menu.Items.Add(new ToolStripMenuItem("⚠ " + err) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(L("Stop"), null, (_, _) => Quit()));
    }

    static string Spaced(string code) => code.Length == 6 ? code[..3] + " " + code[3..] : code;

    void ShowPair()
    {
        if (pairWindow == null || pairWindow.IsDisposed) pairWindow = new PairWindow(core);
        pairWindow.Show();
        pairWindow.Activate();
    }

    void OpenEditor()
    {
        if (editorWindow == null || editorWindow.IsDisposed) editorWindow = new EditorWindow(core.Server.EditorToken);
        editorWindow.Show();
        editorWindow.Activate();
    }

    void ResetLayout()
    {
        var r = MessageBox.Show(L("Je huidige layout.json wordt eerst bewaard als back-up in de Cyberpad-map."), L("Standaard-layout terugzetten?"),
            MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
        if (r == DialogResult.OK) core.Layouts.ResetToDefault();
    }

    static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true })?.Dispose(); } catch { }
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    static bool Autostart
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue("Cyberpad") is string;
        }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) k.SetValue("Cyberpad", "\"" + Environment.ProcessPath + "\"");
            else k.DeleteValue("Cyberpad", false);
        }
    }

    void Quit()
    {
        icon.Visible = false;
        editorWindow?.Close();
        pairWindow?.Close();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { icon.Dispose(); menu.Dispose(); }
        base.Dispose(disposing);
    }
}
