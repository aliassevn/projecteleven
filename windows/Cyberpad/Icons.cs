using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Text.RegularExpressions;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Iconen voor tegels: "app:&lt;naam&gt;" (icoon uit het Startmenu) of "img:&lt;16 hex&gt;.png" (geüpload in de editor).</summary>
static class Icons
{
    public const int MaxUpload = 700 * 1024;
    public const int Size = 256;
    static readonly Regex ImgName = new("^[0-9a-f]{16}\\.png$");
    static readonly Dictionary<string, byte[]> Cache = new();

    public static byte[]? Png(string src, int size)
    {
        size = Math.Clamp(size, 16, 256);
        if (src.StartsWith("img:"))
        {
            var name = src[4..];
            if (!ImgName.IsMatch(name)) return null;
            var file = Path.Combine(Paths.Icons, name);
            return File.Exists(file) ? File.ReadAllBytes(file) : null;
        }
        if (src.StartsWith("app:"))
        {
            var key = src + "@" + size;
            lock (Cache) if (Cache.TryGetValue(key, out var hit)) return hit;
            var png = Apps.IconPng(src[4..], size);
            if (png != null) lock (Cache) Cache[key] = png;
            return png;
        }
        return null;
    }

    /// <summary>Slaat een geüploade afbeelding op als PNG van hooguit 256 px. Geeft "img:&lt;naam&gt;" terug.</summary>
    public static string Store(byte[] raw)
    {
        if (raw.Length > MaxUpload) throw new ActionException(L("Afbeelding te groot (max. 700 KB)"));
        Image img;
        try { img = Image.FromStream(new MemoryStream(raw)); }
        catch { throw new ActionException(L("Dit is geen afbeelding die Cyberpad kan lezen")); }
        using (img)
        {
            var scale = Math.Min(1.0, (double)Size / Math.Max(img.Width, img.Height));
            int w = Math.Max(1, (int)Math.Round(img.Width * scale)), h = Math.Max(1, (int)Math.Round(img.Height * scale));
            using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(img, 0, 0, w, h);
            }
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            var data = ms.ToArray();
            var name = Crypto.Sha256(Convert.ToBase64String(data))[..16] + ".png";
            File.WriteAllBytes(Path.Combine(Paths.Icons, name), data);
            return "img:" + name;
        }
    }
}
