using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>
/// HTTP en WebSocket op poort 7420 (Kestrel, geen beheerdersrechten nodig). Zelfde routes en berichten als de Mac;
/// zie docs\PROTOCOL.md. De tablet stuurt alleen tegel-id's; wat een knop doet blijft op de pc.
/// </summary>
sealed class Server
{
    public const int Port = 7420;
    const int MaxBody = 1024 * 1024;
    const int MaxWsMessage = 64 * 1024;

    readonly Core core;
    readonly ConcurrentDictionary<Guid, Client> clients = new();
    WebApplication? app;
    int statePending;
    public string EditorToken { get; } = Crypto.RandomHex(32);
    public string? Error { get; private set; }
    public DateTime LastActivity { get; private set; } = DateTime.MinValue;

    public Server(Core core) => this.core = core;

    public IEnumerable<string> OnlineDevices => clients.Values.Where(c => c.DeviceId != null).Select(c => c.DeviceId!).Distinct();
    public bool HasClients => clients.Values.Any(c => c.DeviceId != null) || (DateTime.UtcNow - LastActivity).TotalSeconds < 10;

    public async Task StartAsync()
    {
        try
        {
            var builder = WebApplication.CreateSlimBuilder(new WebApplicationOptions { ContentRootPath = AppContext.BaseDirectory });
            builder.Logging.ClearProviders();
            builder.WebHost.ConfigureKestrel(o =>
            {
                o.ListenAnyIP(Port);
                o.Limits.MaxRequestBodySize = MaxBody;
                o.AddServerHeader = false;
            });
            app = builder.Build();
            app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });
            app.Run(Handle);
            await app.StartAsync();
        }
        catch (Exception e)
        {
            Error = L("Server kon niet starten: {0}", e.Message);
        }
    }

    public async Task StopAsync()
    {
        if (app != null) try { await app.StopAsync(); } catch { }
    }

    // ---------------------------------------------------------------- uitsturen

    public void Broadcast(object msg)
    {
        var text = Json.Serialize(msg);
        foreach (var c in clients.Values) if (c.DeviceId != null) c.Send(text);
    }

    public void BroadcastLayout()
    {
        foreach (var c in clients.Values)
            if (c.DeviceId != null) c.Send(Json.Serialize(new Dictionary<string, object?> { ["type"] = "layout", ["layout"] = core.LayoutJson(c.DeviceId) }));
    }

    public void BroadcastState() => Broadcast(new Dictionary<string, object?> { ["type"] = "state", ["state"] = core.FullState() });

    /// <summary>Status hooguit ~7× per seconde uitsturen.</summary>
    public void ScheduleState()
    {
        if (Interlocked.Exchange(ref statePending, 1) == 1) return;
        _ = Task.Delay(150).ContinueWith(_ =>
        {
            Interlocked.Exchange(ref statePending, 0);
            BroadcastState();
        });
    }

    public void Disconnect(string deviceId)
    {
        foreach (var c in clients.Values.Where(c => c.DeviceId == deviceId)) c.Reject();
    }

    // ---------------------------------------------------------------- HTTP

    async Task Handle(HttpContext ctx)
    {
        var remote = ctx.Connection.RemoteIpAddress;
        if (!NetUtil.IsLocal(remote)) { ctx.Abort(); return; } // alleen het lokale netwerk
        var loopback = NetUtil.IsLoopback(remote);
        var path = ctx.Request.Path.Value ?? "/";
        var method = ctx.Request.Method;
        ctx.Response.Headers["Cache-Control"] = "no-store";
        ctx.Response.Headers["X-Content-Type-Options"] = "nosniff";

        try
        {
            if (path == "/ws")
            {
                if (!ctx.WebSockets.IsWebSocketRequest) { await Text(ctx, 400, "Bad request"); return; }
                using var ws = await ctx.WebSockets.AcceptWebSocketAsync();
                await RunClient(ws, remote);
                return;
            }
            if (path.StartsWith("/api/editor/")) { await HandleEditor(ctx, path, method, loopback); return; }
            if (method == "GET" && path == "/api/icon") { await HandleIcon(ctx, loopback); return; }
            if (method == "GET" && path == "/pad.css")
            {
                var css = core.Themes.Css(core.Layouts.Current);
                if (css != null) { await Body(ctx, 200, Encoding.UTF8.GetBytes(css), "text/css; charset=utf-8"); return; }
            }
            if (method == "GET" && path == "/i18n.js")
            {
                await Body(ctx, 200, Encoding.UTF8.GetBytes(I18n.Script()), "application/javascript; charset=utf-8");
                return;
            }
            if (method == "POST" && path == "/api/lang")
            {
                var ok = core.Pairing.Authenticate(Header(ctx, "X-Cyberpad-Token")) != null || EditorAllowed(ctx, loopback);
                if (!ok) { await JsonOut(ctx, 401, new { error = "unauthorized" }); return; }
                var code = Lay.Str(await ReadJson(ctx), "lang") ?? "";
                if (!I18n.IsValid(code)) { await JsonOut(ctx, 400, new { error = "unknown language" }); return; }
                Program.OnUi(() => I18n.Set(code));
                await JsonOut(ctx, 200, new { ok = true, lang = code });
                return;
            }

            switch (method, path)
            {
                case ("GET", "/api/ping"):
                    await JsonOut(ctx, 200, new { ok = true, app = "Cyberpad" });
                    return;
                case ("POST", "/api/pair"):
                {
                    var body = await ReadJson(ctx);
                    var r = core.Pairing.Pair(Lay.Str(body, "code") ?? "", Lay.Str(body, "name") ?? "Tablet", remote?.ToString() ?? "?");
                    switch (r.Result)
                    {
                        case Pairing.Outcome.Ok: await JsonOut(ctx, 200, new { token = r.Token, deviceId = r.Device!.Id }); break;
                        case Pairing.Outcome.Wrong: await JsonOut(ctx, 401, new { error = "wrong", attemptsLeft = r.Number }); break;
                        default: await JsonOut(ctx, 429, new { error = "blocked", seconds = r.Number }); break;
                    }
                    return;
                }
            }

            if (path is "/api/layout" or "/api/state" or "/api/press" or "/api/slider" or "/api/meeting" or "/api/widget" or "/api/photo" or "/api/dial")
            {
                var device = core.Pairing.Authenticate(Header(ctx, "X-Cyberpad-Token"));
                if (device == null) { await JsonOut(ctx, 401, new { error = "unauthorized" }); return; }
                LastActivity = DateTime.UtcNow;
                await HandleDevice(ctx, path, device);
                return;
            }

            if (method == "GET")
            {
                if (path == "/editor" || path.StartsWith("/editor/"))
                {
                    var rest = path["/editor".Length..];
                    await Static(ctx, rest is "" or "/" ? "/index.html" : rest, Paths.Editor);
                }
                else await Static(ctx, path, Paths.Pad);
                return;
            }
            await Text(ctx, 405, "Method not allowed");
        }
        catch (BadHttpRequestException) { try { await Text(ctx, 413, "Too large"); } catch { } }
        catch (Exception) { try { if (!ctx.Response.HasStarted) await Text(ctx, 500, "Error"); } catch { } }
    }

    async Task HandleDevice(HttpContext ctx, string path, Device device)
    {
        if (path == "/api/layout") { await JsonOut(ctx, 200, new Dictionary<string, object?> { ["layout"] = core.LayoutJson(device.Id), ["state"] = core.FullState() }); return; }
        if (path == "/api/state") { await JsonOut(ctx, 200, new Dictionary<string, object?> { ["state"] = core.FullState() }); return; }
        if (path == "/api/photo")
        {
            var tile = Lay.Tile(core.Layouts.Current, ctx.Request.Query["tile"].ToString());
            int.TryParse(ctx.Request.Query["i"].ToString(), out var i);
            var img = tile != null && Lay.Kind(tile) == "photos" ? core.Widgets.Photos.Image(Lay.Config(tile), i) : null;
            if (img == null) { await Text(ctx, 404, L("Geen foto")); return; }
            await Body(ctx, 200, img, "image/jpeg");
            return;
        }
        var body = await ReadJson(ctx);
        (bool Ok, string? Error) r = path switch
        {
            "/api/widget" => core.HandleWidget(Lay.Str(body, "id") ?? "", Lay.Str(body, "action") ?? "", Lay.Num(body, "value")),
            "/api/dial" => core.HandleDial(Lay.Str(body, "id") ?? "", Lay.Int(body, "steps") ?? 0),
            "/api/meeting" => (false, L("Onbekende vergaderactie")),
            _ => core.HandleInput(path == "/api/press" ? "press" : "slider", Lay.Str(body, "id") ?? "", Lay.Str(body, "gesture"), Lay.Num(body, "value")),
        };
        var o = new Dictionary<string, object?> { ["ok"] = r.Ok };
        if (r.Error != null) o["error"] = r.Error;
        await JsonOut(ctx, 200, o);
        ScheduleState();
    }

    bool EditorAllowed(HttpContext ctx, bool loopback)
    {
        if (loopback && Header(ctx, "X-Cyberpad-Editor") is { } t && Crypto.ConstantTimeEqual(t, EditorToken)) return true;
        return core.Pairing.Authenticate(Header(ctx, "X-Cyberpad-Token")) != null;
    }

    async Task HandleEditor(HttpContext ctx, string path, string method, bool loopback)
    {
        // Oude editor-pagina's vroegen eerst toestemming; elke gekoppelde tablet mag nu meteen.
        if (path is "/api/editor/request" or "/api/editor/status")
        {
            if (core.Pairing.Authenticate(Header(ctx, "X-Cyberpad-Token")) == null) { await JsonOut(ctx, 401, new { error = "unauthorized" }); return; }
            await JsonOut(ctx, 200, new { status = "granted" });
            return;
        }
        if (!EditorAllowed(ctx, loopback)) { await JsonOut(ctx, 403, new { error = L("Niet gekoppeld of editor verlopen") }); return; }

        switch (method, path)
        {
            case ("GET", "/api/editor/layout"):
                await JsonOut(ctx, 200, new Dictionary<string, object?> { ["layout"] = core.Layouts.Layout, ["revision"] = core.Layouts.Revision });
                return;
            case ("PUT", "/api/editor/layout"):
            {
                var body = await ReadJson(ctx);
                if (body?["layout"] is not JsonObject l) { await JsonOut(ctx, 400, new { error = L("Geen layout meegestuurd") }); return; }
                var r = core.Layouts.SaveFromEditor((JsonObject)l.DeepClone(), Lay.Str(body, "baseRevision"));
                switch (r.Result)
                {
                    case LayoutStore.SaveResult.Ok: await JsonOut(ctx, 200, new { ok = true, revision = r.Revision }); break;
                    case LayoutStore.SaveResult.Conflict: await JsonOut(ctx, 409, new { ok = false, errors = new[] { L("De layout is intussen elders gewijzigd. Laad opnieuw.") } }); break;
                    default: await JsonOut(ctx, 422, new { ok = false, errors = r.Errors }); break;
                }
                return;
            }
            case ("POST", "/api/editor/validate"):
            {
                var body = await ReadJson(ctx);
                if (body?["layout"] is not JsonObject l) { await JsonOut(ctx, 400, new { error = L("Geen layout") }); return; }
                await JsonOut(ctx, 200, new { errors = LayoutStore.Problems(l) });
                return;
            }
            case ("GET", "/api/editor/themes"):
                core.Themes.Reload();
                await JsonOut(ctx, 200, new JsonArray(core.Themes.All.Select(t => (JsonNode)t).ToArray()));
                return;
            case ("POST", "/api/editor/icon"):
            {
                var data = Lay.Str(await ReadJson(ctx), "data");
                if (data == null) { await JsonOut(ctx, 400, new { error = L("Geen afbeelding meegestuurd") }); return; }
                var comma = data.StartsWith("data:") ? data.IndexOf(',') : -1;
                byte[] raw;
                try { raw = Convert.FromBase64String(comma >= 0 ? data[(comma + 1)..] : data); }
                catch { await JsonOut(ctx, 400, new { error = L("Geen afbeelding meegestuurd") }); return; }
                try { await JsonOut(ctx, 200, new { icon = Icons.Store(raw) }); }
                catch (ActionException e) { await JsonOut(ctx, 422, new { error = e.Message }); }
                return;
            }
            case ("GET", "/api/editor/catalog"):
                await JsonOut(ctx, 200, core.EditorCatalog());
                return;
        }
        await JsonOut(ctx, 404, new { error = L("Onbekend") });
    }

    async Task HandleIcon(HttpContext ctx, bool loopback)
    {
        if (!EditorAllowed(ctx, loopback)) { await JsonOut(ctx, 401, new { error = "unauthorized" }); return; }
        int size = int.TryParse(ctx.Request.Query["size"].ToString(), out var s) ? s : Icons.Size;
        var src = ctx.Request.Query["src"].ToString();
        var png = string.IsNullOrEmpty(src) ? null : Icons.Png(src, size);
        if (png == null) { await Text(ctx, 404, L("Geen icoon")); return; }
        await Body(ctx, 200, png, "image/png");
    }

    static readonly Dictionary<string, string> Types = new()
    {
        [".html"] = "text/html; charset=utf-8", [".js"] = "application/javascript; charset=utf-8", [".css"] = "text/css; charset=utf-8",
        [".json"] = "application/json", [".png"] = "image/png", [".svg"] = "image/svg+xml", [".ttf"] = "font/ttf", [".woff2"] = "font/woff2",
        [".ico"] = "image/x-icon",
    };

    static async Task Static(HttpContext ctx, string rawPath, string root)
    {
        var p = Uri.UnescapeDataString(rawPath);
        if (p == "/") p = "/index.html";
        var parts = p.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || parts.Any(x => x == ".." || x.StartsWith('.') || x.Contains('\\') || x.Contains(':'))) { await Text(ctx, 404, "Not found"); return; }
        var rootFull = Path.GetFullPath(root);
        var file = Path.GetFullPath(Path.Combine(new[] { rootFull }.Concat(parts).ToArray()));
        if (!file.StartsWith(rootFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(file)) { await Text(ctx, 404, "Not found"); return; }
        var type = Types.TryGetValue(Path.GetExtension(file).ToLowerInvariant(), out var t) ? t : "application/octet-stream";
        await Body(ctx, 200, await File.ReadAllBytesAsync(file), type);
    }

    // ---------------------------------------------------------------- hulpjes

    static string? Header(HttpContext ctx, string name) => ctx.Request.Headers.TryGetValue(name, out var v) ? v.ToString() : null;

    static async Task<JsonObject?> ReadJson(HttpContext ctx)
    {
        try
        {
            using var reader = new StreamReader(ctx.Request.Body, Encoding.UTF8);
            var text = await reader.ReadToEndAsync();
            if (text.Length > MaxBody) return null;
            return JsonNode.Parse(text) as JsonObject;
        }
        catch { return null; }
    }

    static Task Body(HttpContext ctx, int status, byte[] data, string type)
    {
        ctx.Response.StatusCode = status;
        ctx.Response.ContentType = type;
        ctx.Response.ContentLength = data.Length;
        return ctx.Response.Body.WriteAsync(data).AsTask();
    }

    static Task JsonOut(HttpContext ctx, int status, object o) => Body(ctx, status, Encoding.UTF8.GetBytes(Json.Serialize(o)), "application/json");
    static Task Text(HttpContext ctx, int status, string s) => Body(ctx, status, Encoding.UTF8.GetBytes(s), "text/plain; charset=utf-8");

    // ---------------------------------------------------------------- WebSocket

    sealed class Client
    {
        public readonly WebSocket Ws;
        public string? DeviceId;
        public readonly Channel<string> Out = Channel.CreateBounded<string>(new BoundedChannelOptions(256) { FullMode = BoundedChannelFullMode.DropOldest });
        public DateTime LastPointerError = DateTime.MinValue;
        public bool UsedPointer;
        public volatile bool Closing;
        public Client(WebSocket ws) => Ws = ws;
        public void Send(string text) { if (!Closing) Out.Writer.TryWrite(text); }
        public void Reject()
        {
            Send("{\"type\":\"unauthorized\"}");
            Closing = true;
            Out.Writer.TryComplete();
        }
    }

    async Task RunClient(WebSocket ws, IPAddress? remote)
    {
        var c = new Client(ws);
        var id = Guid.NewGuid();
        clients[id] = c;
        using var cts = new CancellationTokenSource();
        var sender = Task.Run(async () =>
        {
            try
            {
                await foreach (var msg in c.Out.Reader.ReadAllAsync(cts.Token))
                    await ws.SendAsync(Encoding.UTF8.GetBytes(msg), WebSocketMessageType.Text, true, cts.Token);
                if (ws.State == WebSocketState.Open)
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
            }
            catch { }
        });
        // Binnen 10 seconden moet er een geldig "hello" met token komen.
        _ = Task.Delay(10_000).ContinueWith(_ => { if (c.DeviceId == null) c.Reject(); });

        var buffer = new byte[16 * 1024];
        try
        {
            while (ws.State == WebSocketState.Open && !c.Closing)
            {
                using var ms = new MemoryStream();
                WebSocketReceiveResult res;
                do
                {
                    res = await ws.ReceiveAsync(buffer, cts.Token);
                    if (res.MessageType == WebSocketMessageType.Close) break;
                    ms.Write(buffer, 0, res.Count);
                    if (ms.Length > MaxWsMessage) throw new InvalidOperationException("te groot");
                } while (!res.EndOfMessage);
                if (res.MessageType == WebSocketMessageType.Close) break;
                if (res.MessageType != WebSocketMessageType.Text) continue;
                OnMessage(c, Encoding.UTF8.GetString(ms.ToArray()));
            }
        }
        catch { }
        finally
        {
            clients.TryRemove(id, out _);
            c.Closing = true;
            c.Out.Writer.TryComplete();
            if (c.UsedPointer) try { Native.Button(false); } catch { } // slepen niet laten hangen
            try { await sender.WaitAsync(TimeSpan.FromSeconds(2)); } catch { }
            cts.Cancel();
            core.ClientsChanged();
        }
    }

    void OnMessage(Client c, string text)
    {
        JsonObject? msg;
        try { msg = JsonNode.Parse(text) as JsonObject; } catch { return; }
        var type = Lay.Str(msg, "type");
        if (msg == null || type == null) return;

        if (type == "hello")
        {
            var device = core.Pairing.Authenticate(Lay.Str(msg, "token"));
            if (device == null) { c.Reject(); return; }
            c.DeviceId = device.Id;
            c.Send(Json.Serialize(new { type = "welcome", device = device.Name }));
            c.Send(Json.Serialize(new Dictionary<string, object?> { ["type"] = "layout", ["layout"] = core.LayoutJson(device.Id) }));
            c.Send(Json.Serialize(new Dictionary<string, object?> { ["type"] = "state", ["state"] = core.FullState() }));
            core.ClientsChanged();
            return;
        }
        if (c.DeviceId == null) { c.Reject(); return; }
        LastActivity = DateTime.UtcNow;
        var tileId = Lay.Str(msg, "id") ?? "";

        void ack(string id, bool ok, string? error)
        {
            var a = new Dictionary<string, object?> { ["type"] = "ack", ["id"] = id, ["ok"] = ok };
            if (error != null) a["error"] = error;
            c.Send(Json.Serialize(a));
        }

        switch (type)
        {
            case "ping":
                c.Send("{\"type\":\"pong\"}");
                break;
            case "viewport":
                core.Pairing.SetViewport(c.DeviceId, new Viewport(Lay.Int(msg, "w") ?? 0, Lay.Int(msg, "h") ?? 0, Lay.Int(msg, "vw") ?? 0, Lay.Int(msg, "vh") ?? 0));
                break;
            case "widget":
            {
                var r = core.HandleWidget(tileId, Lay.Str(msg, "action") ?? "", Lay.Num(msg, "value"));
                if (!r.Ok) ack(tileId, false, r.Error);
                ScheduleState();
                break;
            }
            case "pointer":
            {
                c.UsedPointer = true;
                var r = core.HandlePointer(tileId, msg);
                // Fouten hooguit eens per 3 s melden, niet bij elke beweging.
                if (!r.Ok && (DateTime.UtcNow - c.LastPointerError).TotalSeconds > 3)
                {
                    c.LastPointerError = DateTime.UtcNow;
                    ack(tileId, false, r.Error);
                }
                break;
            }
            case "dial":
            {
                var r = core.HandleDial(tileId, Lay.Int(msg, "steps") ?? 0);
                if (!r.Ok) ack(tileId, false, r.Error);
                ScheduleState();
                break;
            }
            case "meeting":
                ack("meeting", false, L("Onbekende vergaderactie"));
                break;
            case "press":
            case "slider":
            {
                var r = core.HandleInput(type, tileId, Lay.Str(msg, "gesture"), Lay.Num(msg, "value"));
                if (type == "press" || !r.Ok) ack(tileId, r.Ok, r.Error);
                ScheduleState();
                break;
            }
        }
    }
}
