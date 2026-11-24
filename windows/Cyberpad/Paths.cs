namespace Cyberpad;

/// <summary>Waar Cyberpad zijn bestanden zoekt en bewaart.</summary>
static class Paths
{
    /// <summary>%APPDATA%\Cyberpad: layout.json, devices.json, settings.json, Icons\.</summary>
    public static readonly string Support = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Cyberpad");

    /// <summary>Gedeelde onderdelen (tablet-pagina, editor, thema's, talen, catalogus).
    /// Geïnstalleerd: shared\ naast Cyberpad.exe. Ontwikkelen: de map shared\ in de repo.</summary>
    public static readonly string Shared = FindShared();

    public static string Pad => Path.Combine(Shared, "pad");
    public static string Editor => Path.Combine(Shared, "editor");
    public static string Themes => Path.Combine(Shared, "themes");
    public static string I18n => Path.Combine(Shared, "i18n");
    public static string Catalog => Path.Combine(Shared, "catalog");
    public static string Icons => Path.Combine(Support, "Icons");

    static string FindShared()
    {
        var env = Environment.GetEnvironmentVariable("CYBERPAD_SHARED_DIR");
        if (!string.IsNullOrEmpty(env) && Directory.Exists(env)) return env;
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        for (var d = dir; d != null; d = d.Parent)
        {
            var candidate = Path.Combine(d.FullName, "shared");
            if (Directory.Exists(Path.Combine(candidate, "pad"))) return candidate;
        }
        return Path.Combine(AppContext.BaseDirectory, "shared");
    }

    public static void Ensure()
    {
        Directory.CreateDirectory(Support);
        Directory.CreateDirectory(Icons);
    }
}
