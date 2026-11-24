using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Apps uit het Startmenu, browsers en app-iconen.</summary>
static class Apps
{
    sealed record AppEntry(string Name, string Path);

    static readonly object Gate = new();
    static (DateTime At, List<AppEntry> List)? cache;

    static IEnumerable<string> StartMenuDirs() => new[]
    {
        Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
        Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
    }.Where(d => !string.IsNullOrEmpty(d)).Select(d => Path.Combine(d, "Programs")).Where(Directory.Exists);

    static List<AppEntry> Installed()
    {
        lock (Gate)
        {
            if (cache is { } c && (DateTime.UtcNow - c.At).TotalMinutes < 5) return c.List;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var list = new List<AppEntry>();
            foreach (var dir in StartMenuDirs())
            {
                IEnumerable<string> files;
                try { files = Directory.EnumerateFiles(dir, "*.lnk", SearchOption.AllDirectories).ToList(); } catch { continue; }
                foreach (var f in files)
                {
                    var name = System.IO.Path.GetFileNameWithoutExtension(f);
                    var low = name.ToLowerInvariant();
                    if (low.Contains("uninstall") || low.Contains("verwijder") || low.Contains("readme") || low.Contains("help")) continue;
                    if (seen.Add(name)) list.Add(new AppEntry(name, f));
                }
            }
            list.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase));
            cache = (DateTime.UtcNow, list);
            return list;
        }
    }

    /// <summary>Voor de editor: [{id, name}]. Het id is de naam uit het Startmenu.</summary>
    public static List<Dictionary<string, string>> Catalog() =>
        Installed().Select(a => new Dictionary<string, string> { ["id"] = a.Name, ["name"] = a.Name }).ToList();

    /// <summary>Pad naar iets dat Windows kan starten: een bestaand pad, een snelkoppeling uit het Startmenu, of null.</summary>
    static string? Resolve(string app)
    {
        var expanded = Environment.ExpandEnvironmentVariables(app.Trim().Trim('"'));
        if (File.Exists(expanded) || Directory.Exists(expanded)) return expanded;
        var hit = Installed().FirstOrDefault(a => string.Equals(a.Name, app, StringComparison.OrdinalIgnoreCase));
        return hit?.Path;
    }

    /// <summary>App starten: naam uit het Startmenu, pad naar .exe/.lnk, of een naam die Windows zelf kent (notepad, chrome…).</summary>
    public static void Open(string app)
    {
        if (string.IsNullOrWhiteSpace(app)) throw new ActionException(L("Ontbreekt in layout: {0}", "app"));
        var target = Resolve(app) ?? app;
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true })?.Dispose();
        }
        catch (Exception)
        {
            throw new ActionException(L("App niet gevonden: {0}", app));
        }
    }

    // ---------- Browsers ----------

    public sealed record Browser(string Id, string Name, string Exe, bool IsDefault);

    static string? ExeFromCommand(string? cmd)
    {
        if (string.IsNullOrWhiteSpace(cmd)) return null;
        cmd = cmd.Trim();
        if (cmd.StartsWith('"')) { var end = cmd.IndexOf('"', 1); return end > 1 ? cmd[1..end] : null; }
        var i = cmd.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        return i > 0 ? cmd[..(i + 4)] : cmd.Split(' ')[0];
    }

    /// <summary>Geregistreerde browsers (StartMenuInternet), de standaardbrowser eerst.</summary>
    public static List<Browser> Browsers()
    {
        string? defaultExe = null;
        try
        {
            using var uc = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice");
            if (uc?.GetValue("ProgId") is string progId)
            {
                using var cmdKey = Registry.ClassesRoot.OpenSubKey(progId + @"\shell\open\command");
                defaultExe = ExeFromCommand(cmdKey?.GetValue(null) as string);
            }
        }
        catch { }

        var list = new List<Browser>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            try
            {
                using var root = hive.OpenSubKey(@"SOFTWARE\Clients\StartMenuInternet");
                if (root == null) continue;
                foreach (var keyName in root.GetSubKeyNames())
                {
                    using var k = root.OpenSubKey(keyName);
                    using var cmd = k?.OpenSubKey(@"shell\open\command");
                    var exe = ExeFromCommand(cmd?.GetValue(null) as string);
                    if (exe == null || !File.Exists(exe) || !seen.Add(exe)) continue;
                    var name = k?.GetValue(null) as string ?? keyName;
                    var isDef = defaultExe != null && string.Equals(System.IO.Path.GetFullPath(exe), System.IO.Path.GetFullPath(defaultExe), StringComparison.OrdinalIgnoreCase);
                    list.Add(new Browser(keyName, name, exe, isDef));
                }
            }
            catch { }
        }
        return list.OrderByDescending(b => b.IsDefault).ThenBy(b => b.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    /// <summary>Link openen in de standaardbrowser, of in een gekozen browser (id uit Browsers(), naam of pad).</summary>
    public static void OpenUrl(string url, string? browser)
    {
        if (string.IsNullOrWhiteSpace(browser))
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true })?.Dispose();
            return;
        }
        var b = Browsers().FirstOrDefault(x => string.Equals(x.Id, browser, StringComparison.OrdinalIgnoreCase)
                                             || string.Equals(x.Name, browser, StringComparison.OrdinalIgnoreCase));
        var exe = b?.Exe ?? Resolve(browser) ?? browser;
        try
        {
            var psi = new ProcessStartInfo(exe) { UseShellExecute = true };
            psi.ArgumentList.Add(url);
            Process.Start(psi)?.Dispose();
        }
        catch
        {
            throw new ActionException(L("App niet gevonden: {0}", browser));
        }
    }

    // ---------- Iconen (app:<naam>) ----------

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItemImageFactory
    {
        [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct SIZE { public int cx; public int cy; }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);

    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(IntPtr h);

    /// <summary>PNG van het icoon van een app (naam uit het Startmenu of pad), of null.</summary>
    public static byte[]? IconPng(string app, int size)
    {
        var path = Resolve(app);
        if (path == null) return null;
        try
        {
            var iid = typeof(IShellItemImageFactory).GUID;
            SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out var factory);
            // SIIGBF_ICONONLY (0x4): het icoon, geen miniatuur van de inhoud.
            if (factory.GetImage(new SIZE { cx = size, cy = size }, 0x4, out var hbm) != 0) return null;
            try
            {
                using var bmp = ToBitmapWithAlpha(hbm);
                using var ms = new MemoryStream();
                bmp.Save(ms, ImageFormat.Png);
                return ms.ToArray();
            }
            finally { DeleteObject(hbm); }
        }
        catch { return null; }
    }

    /// <summary>Image.FromHbitmap gooit de doorzichtigheid weg; daarom de pixels zelf kopiëren.</summary>
    static Bitmap ToBitmapWithAlpha(IntPtr hbm)
    {
        using var src = Image.FromHbitmap(hbm);
        var rect = new Rectangle(0, 0, src.Width, src.Height);
        var data = src.LockBits(rect, ImageLockMode.ReadOnly, src.PixelFormat);
        try
        {
            if (src.PixelFormat == PixelFormat.Format32bppRgb || src.PixelFormat == PixelFormat.Format32bppArgb)
            {
                using var copy = new Bitmap(data.Width, data.Height, data.Stride, PixelFormat.Format32bppArgb, data.Scan0);
                return new Bitmap(copy); // eigen kopie, los van de vergrendelde bron
            }
        }
        finally { src.UnlockBits(data); }
        return new Bitmap(src);
    }
}
