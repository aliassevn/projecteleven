using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>
/// Laadt %APPDATA%\Cyberpad\layout.json en houdt het bestand in de gaten, zodat bewerken direct doorkomt.
/// De layout blijft een JsonObject: zelfde formaat als op de Mac, en velden die Windows (nog) niet kent blijven bewaard.
/// </summary>
sealed class LayoutStore
{
    public const int MaxColumns = 12;
    public const int MaxRows = 8;

    readonly object gate = new();
    readonly System.Threading.Timer watcher;
    DateTime? mtime;
    JsonObject layout;

    public string FilePath { get; } = Path.Combine(Paths.Support, "layout.json");
    public string? LastError { get; private set; }
    public event Action? Changed;

    public LayoutStore()
    {
        layout = DefaultLayout.Build();
        if (!File.Exists(FilePath)) Save(layout);
        Reload();
        watcher = new System.Threading.Timer(_ => CheckForChanges(), null, 1500, 1500);
    }

    /// <summary>Een kopie: wie hem aanpast, verandert de opgeslagen layout niet.</summary>
    public JsonObject Layout { get { lock (gate) return (JsonObject)layout.DeepClone(); } }

    /// <summary>Alleen lezen, zonder kopie (niet aanpassen!).</summary>
    public JsonObject Current { get { lock (gate) return layout; } }

    public void Save(JsonObject l)
    {
        lock (gate) Files.WriteAtomic(FilePath, l.ToJsonString(Json.Pretty));
    }

    public string Revision
    {
        get
        {
            try { return Crypto.Sha256(File.ReadAllText(FilePath)); } catch { return ""; }
        }
    }

    public string? ResetToDefault()
    {
        string? backup = null;
        if (File.Exists(FilePath))
        {
            backup = Path.Combine(Paths.Support, $"layout-backup-{DateTime.Now:yyyyMMdd-HHmmss}.json");
            try { File.Copy(FilePath, backup, true); } catch { backup = null; }
        }
        Save(DefaultLayout.Build());
        Reload();
        return backup;
    }

    public enum SaveResult { Ok, Conflict, Invalid }

    /// <summary>Opslaan vanuit de editor: alleen als niemand anders intussen iets veranderde, met back-up (laatste 20).</summary>
    public (SaveResult Result, string? Revision, List<string>? Errors) SaveFromEditor(JsonObject l, string? baseRevision)
    {
        if (baseRevision != null && baseRevision != Revision) return (SaveResult.Conflict, null, null);
        var problems = Problems(l);
        if (problems.Count > 0) return (SaveResult.Invalid, null, problems);
        try
        {
            if (File.Exists(FilePath))
                File.Copy(FilePath, Path.Combine(Paths.Support, $"layout-backup-editor-{DateTime.Now:yyyyMMdd-HHmmss-fff}.json"), true);
            var old = Directory.GetFiles(Paths.Support, "layout-backup-editor-*").OrderBy(f => f, StringComparer.Ordinal).ToList();
            foreach (var f in old.Take(Math.Max(0, old.Count - 20))) File.Delete(f);
        }
        catch { }
        Save(l);
        Reload();
        return (SaveResult.Ok, Revision, null);
    }

    void CheckForChanges()
    {
        try
        {
            var m = File.Exists(FilePath) ? File.GetLastWriteTimeUtc(FilePath) : (DateTime?)null;
            if (m != mtime) Reload();
        }
        catch { }
    }

    void Reload()
    {
        bool changed = false;
        lock (gate)
        {
            try
            {
                mtime = File.GetLastWriteTimeUtc(FilePath);
                var node = JsonNode.Parse(File.ReadAllText(FilePath)) as JsonObject ?? throw new Exception("geen object");
                if (Lay.Arr(node, "pages").Count() == 0) throw new Exception("geen pagina's");
                LastError = null;
                if (!JsonNode.DeepEquals(node, layout)) { layout = node; changed = true; }
            }
            catch (Exception e)
            {
                LastError = L("layout.json kon niet worden gelezen: {0}", e.Message);
            }
        }
        if (changed) Changed?.Invoke();
    }

    // ---------- Controle (editor) ----------

    static readonly Regex ColorRe = new("^#[0-9a-fA-F]{6}$");
    public static bool ValidColor(string? s) => s != null && ColorRe.IsMatch(s);

    static int? Minutes(string? s)
    {
        if (s == null) return null;
        var p = s.Split(':');
        if (p.Length != 2 || !int.TryParse(p[0], out var h) || !int.TryParse(p[1], out var m) || h < 0 || h > 23 || m < 0 || m > 59) return null;
        return h * 60 + m;
    }

    /// <summary>Fouten die opslaan tegenhouden (zelfde regels als op de Mac). Leeg = in orde.</summary>
    public static List<string> Problems(JsonObject l)
    {
        var o = new List<string>();
        int columns = Lay.Int(l, "columns") ?? 0, rows = Lay.Int(l, "rows") ?? 0;
        if (columns < 1 || columns > MaxColumns) o.Add(L("Kolommen moet tussen 1 en {0} liggen", MaxColumns));
        if (rows < 1 || rows > MaxRows) o.Add(L("Rijen moet tussen 1 en {0} liggen", MaxRows));
        var pages = Lay.Pages(l).ToList();
        if (pages.Count == 0) o.Add(L("Er moet minstens één pagina zijn"));
        var pageIds = new HashSet<string>(); var tileIds = new HashSet<string>();
        foreach (var p in pages)
        {
            var pid = Lay.Str(p, "id") ?? ""; var pname = Lay.Str(p, "name") ?? "";
            int c = Lay.Int(p, "columns") ?? columns, r = Lay.Int(p, "rows") ?? rows;
            if (c < 1 || c > MaxColumns || r < 1 || r > MaxRows) o.Add(L("Raster van {0} moet tussen 1×1 en {1}×{2} liggen", pname, MaxColumns, MaxRows));
            if (pid.Length == 0 || !pageIds.Add(pid)) o.Add(L("Pagina-id “{0}” is leeg of dubbel", pid));
            if (pname.Trim().Length == 0) o.Add(L("Pagina “{0}” heeft geen naam", pid));
            var taken = new HashSet<int>();
            foreach (var t in Lay.Tiles(p))
            {
                var tid = Lay.Str(t, "id") ?? ""; var label = Lay.Str(t, "label") ?? "";
                if (tid.Length == 0 || !tileIds.Add(tid)) o.Add(L("Tegel-id “{0}” is leeg of dubbel", tid));
                int x = Lay.Int(t, "x") ?? -1, y = Lay.Int(t, "y") ?? -1, w = Lay.Int(t, "w") ?? 1, h = Lay.Int(t, "h") ?? 1;
                if (x < 0 || y < 0 || w < 1 || h < 1 || x + w > c || y + h > r)
                {
                    o.Add(L("“{0}” op {1} valt buiten het raster", label, pname));
                    continue;
                }
                for (var dy = 0; dy < h; dy++)
                    for (var dx = 0; dx < w; dx++)
                        if (!taken.Add((y + dy) * 100 + x + dx)) o.Add(L("“{0}” op {1} overlapt een andere tegel", label, pname));
                var color = Lay.Str(t, "color");
                if (color != null && !ValidColor(color)) o.Add(L("Kleur van “{0}” moet als #rrggbb", label));
                var icon = Lay.Str(t, "icon");
                if (icon != null && icon.Length > 300) o.Add(L("Icoon van “{0}” is te lang", label));
            }
        }
        var profileIds = new HashSet<string>();
        foreach (var pr in Lay.Arr(l, "profiles"))
        {
            var id = Lay.Str(pr, "id") ?? ""; var name = Lay.Str(pr, "name") ?? "";
            if (id.Length == 0 || !profileIds.Add(id)) o.Add(L("Profiel-id “{0}” is leeg of dubbel", id));
            foreach (var pid in Lay.StrList(pr, "pages"))
                if (!pageIds.Contains(pid)) o.Add(L("Profiel “{0}” noemt een onbekende pagina “{1}”", name, pid));
            foreach (var rule in Lay.Arr(pr, "when"))
            {
                var from = Lay.Str(rule, "from"); var to = Lay.Str(rule, "to");
                if ((from != null && Minutes(from) == null) || (to != null && Minutes(to) == null)) o.Add($"Profiel “{name}”: tijd moet als UU:MM");
            }
        }
        o.AddRange(ThemeStore.OverrideProblems(Lay.Obj(l, "themeOverrides")));
        return o.Distinct().ToList();
    }

    // ---------- Profielen (tijdregels) ----------

    static bool RuleMatches(JsonObject rule, DateTime now)
    {
        List<int>? days = rule["days"] is JsonArray a ? a.Select(d => d is JsonValue v && v.TryGetValue(out int i) ? i : 0).ToList() : null;
        int dow = now.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)now.DayOfWeek; // 1 = maandag
        int cur = now.Hour * 60 + now.Minute;
        int f = Minutes(Lay.Str(rule, "from")) ?? 0, t = Minutes(Lay.Str(rule, "to")) ?? 24 * 60;
        bool dayOk(int d) => days == null || days.Contains(d);
        if (f <= t) return dayOk(dow) && cur >= f && cur < t;
        if (cur >= f) return dayOk(dow);
        if (cur < t) return dayOk(dow == 1 ? 7 : dow - 1);
        return false;
    }

    /// <summary>Welk profiel geldt: vast per tablet, anders de eerste passende tijdregel, anders het standaardprofiel.</summary>
    public static JsonObject? ActiveProfile(JsonObject l, string? deviceProfile, DateTime now)
    {
        var profiles = Lay.Arr(l, "profiles").ToList();
        if (profiles.Count == 0) return null;
        if (deviceProfile != null && profiles.FirstOrDefault(p => Lay.Str(p, "id") == deviceProfile) is { } fixedP) return fixedP;
        foreach (var p in profiles)
            if (Lay.Arr(p, "when").Any(r => RuleMatches(r, now))) return p;
        return profiles.FirstOrDefault(p => Lay.Bool(p, "default") == true) ?? profiles[0];
    }
}
