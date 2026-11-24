using System.Text.Json.Nodes;

namespace Cyberpad;

/// <summary>Kleine instellingen in %APPDATA%\Cyberpad\settings.json (bijv. de taal).</summary>
static class Settings
{
    static readonly object Lock = new();
    static string FilePath => Path.Combine(Paths.Support, "settings.json");

    public static string? Get(string key)
    {
        lock (Lock)
        {
            try { return JsonNode.Parse(File.ReadAllText(FilePath))?[key]?.GetValue<string>(); }
            catch { return null; }
        }
    }

    public static void Set(string key, string value)
    {
        lock (Lock)
        {
            JsonObject obj;
            try { obj = JsonNode.Parse(File.ReadAllText(FilePath))?.AsObject() ?? new JsonObject(); }
            catch { obj = new JsonObject(); }
            obj[key] = value;
            Files.WriteAtomic(FilePath, obj.ToJsonString(Json.Pretty));
        }
    }
}
