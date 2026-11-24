using System.Runtime.InteropServices;
using Microsoft.Win32;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Toetsen, tekst en muis via SendInput, plus een paar systeemfuncties (vergrendelen, scherm uit…).</summary>
static class Native
{
    // ---------- SendInput ----------

    const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    const uint KEYEVENTF_EXTENDEDKEY = 0x1, KEYEVENTF_KEYUP = 0x2, KEYEVENTF_UNICODE = 0x4;
    const uint MOUSEEVENTF_MOVE = 0x1, MOUSEEVENTF_LEFTDOWN = 0x2, MOUSEEVENTF_LEFTUP = 0x4,
        MOUSEEVENTF_RIGHTDOWN = 0x8, MOUSEEVENTF_RIGHTUP = 0x10, MOUSEEVENTF_WHEEL = 0x800, MOUSEEVENTF_HWHEEL = 0x1000;

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion U; }

    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    static void Send(List<INPUT> inputs)
    {
        if (inputs.Count == 0) return;
        var sent = SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<INPUT>());
        if (sent == 0) throw new ActionException(L("Windows liet de toetsen niet door (misschien staat er een programma met beheerdersrechten vooraan)"));
    }

    static INPUT Key(ushort vk, bool up)
    {
        uint flags = up ? KEYEVENTF_KEYUP : 0;
        if (Extended.Contains(vk)) flags |= KEYEVENTF_EXTENDEDKEY;
        return new INPUT { type = INPUT_KEYBOARD, U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = flags } } };
    }

    // Toetsen die de "extended"-vlag nodig hebben (pijltjes, Home/End, Insert/Delete, PageUp/Down, Win…).
    static readonly HashSet<ushort> Extended = new() { 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, 0x5B, 0x5C, 0x6F, 0x90, 0x2C,
        0xAD, 0xAE, 0xAF, 0xB0, 0xB1, 0xB2, 0xB3 };

    public static void Tap(ushort vk) => Send(new List<INPUT> { Key(vk, false), Key(vk, true) });

    // ---------- Toetscombinaties ("ctrl+shift+a") ----------

    public sealed record Combo(ushort Key, ushort[] Modifiers);

    static readonly Dictionary<string, ushort> Mods = new()
    {
        // Op Windows wordt cmd (⌘) Ctrl, zodat een layout van de Mac meestal gewoon werkt.
        ["cmd"] = 0x11, ["command"] = 0x11, ["⌘"] = 0x11, ["ctrl"] = 0x11, ["control"] = 0x11, ["⌃"] = 0x11,
        ["shift"] = 0x10, ["⇧"] = 0x10,
        ["alt"] = 0x12, ["option"] = 0x12, ["opt"] = 0x12, ["⌥"] = 0x12,
        ["win"] = 0x5B, ["windows"] = 0x5B, ["super"] = 0x5B, ["meta"] = 0x5B,
    };

    static readonly Dictionary<string, ushort> Keys = BuildKeys();

    static Dictionary<string, ushort> BuildKeys()
    {
        var m = new Dictionary<string, ushort>
        {
            ["return"] = 0x0D, ["enter"] = 0x0D, ["tab"] = 0x09, ["space"] = 0x20, ["backspace"] = 0x08, ["delete"] = 0x08,
            ["forwarddelete"] = 0x2E, ["del"] = 0x2E, ["insert"] = 0x2D, ["escape"] = 0x1B, ["esc"] = 0x1B,
            ["home"] = 0x24, ["end"] = 0x23, ["pageup"] = 0x21, ["pagedown"] = 0x22,
            ["left"] = 0x25, ["up"] = 0x26, ["right"] = 0x27, ["down"] = 0x28,
            ["printscreen"] = 0x2C, ["prtsc"] = 0x2C, ["capslock"] = 0x14, ["menu"] = 0x5D, ["pause"] = 0x13,
            ["`"] = 0xC0, ["-"] = 0xBD, ["minus"] = 0xBD, ["="] = 0xBB, ["plus"] = 0xBB, ["["] = 0xDB, ["]"] = 0xDD,
            [";"] = 0xBA, ["'"] = 0xDE, [","] = 0xBC, ["."] = 0xBE, ["/"] = 0xBF, ["\\"] = 0xDC,
            ["volumeup"] = 0xAF, ["volumedown"] = 0xAE, ["mute"] = 0xAD,
            ["playpause"] = 0xB3, ["nexttrack"] = 0xB0, ["prevtrack"] = 0xB1,
        };
        for (var c = 'a'; c <= 'z'; c++) m[c.ToString()] = (ushort)char.ToUpperInvariant(c);
        for (var c = '0'; c <= '9'; c++) m[c.ToString()] = c;
        for (var i = 1; i <= 24; i++) m["f" + i] = (ushort)(0x70 + i - 1);
        return m;
    }

    public static Combo Parse(string s)
    {
        var lower = s.ToLowerInvariant();
        var parts = lower.Split('+').Select(p => p.Trim()).ToList();
        if (lower.EndsWith("++")) { parts = parts.Where(p => p.Length > 0).ToList(); parts.Add("plus"); }
        if (parts.Count == 0 || parts[^1].Length == 0) throw new ActionException(L("Onbekende toetscombinatie: {0}", s));
        var mods = new List<ushort>();
        foreach (var m in parts.Take(parts.Count - 1))
        {
            if (m == "fn") continue;
            if (!Mods.TryGetValue(m, out var vk)) throw new ActionException(L("Onbekende toetscombinatie: {0}", s));
            if (!mods.Contains(vk)) mods.Add(vk);
        }
        if (!Keys.TryGetValue(parts[^1], out var key)) throw new ActionException(L("Onbekende toetscombinatie: {0}", s));
        return new Combo(key, mods.ToArray());
    }

    public static void Press(Combo c)
    {
        var list = new List<INPUT>();
        foreach (var m in c.Modifiers) list.Add(Key(m, false));
        list.Add(Key(c.Key, false));
        list.Add(Key(c.Key, true));
        foreach (var m in c.Modifiers.Reverse()) list.Add(Key(m, true));
        Send(list);
    }

    public const int MaxTextLength = 2000;

    /// <summary>Typt tekst als Unicode, onafhankelijk van de toetsenbordindeling.</summary>
    public static void Type(string text)
    {
        if (text.Length > MaxTextLength) text = text[..MaxTextLength];
        var list = new List<INPUT>();
        foreach (var ch in text.Replace("\r\n", "\n"))
        {
            if (ch == '\n') { list.Add(Key(0x0D, false)); list.Add(Key(0x0D, true)); continue; }
            list.Add(new INPUT { type = INPUT_KEYBOARD, U = new InputUnion { ki = new KEYBDINPUT { wScan = ch, dwFlags = KEYEVENTF_UNICODE } } });
            list.Add(new INPUT { type = INPUT_KEYBOARD, U = new InputUnion { ki = new KEYBDINPUT { wScan = ch, dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP } } });
        }
        for (var i = 0; i < list.Count; i += 40) Send(list.GetRange(i, Math.Min(40, list.Count - i)));
    }

    // ---------- Muis (aanraakpad) ----------

    static INPUT Mouse(uint flags, int dx = 0, int dy = 0, int data = 0) =>
        new() { type = INPUT_MOUSE, U = new InputUnion { mi = new MOUSEINPUT { dx = dx, dy = dy, mouseData = unchecked((uint)data), dwFlags = flags } } };

    public static void MouseMove(double dx, double dy, double speed)
    {
        var s = Math.Clamp(speed, 0.2, 5);
        int x = (int)Math.Round(Math.Clamp(dx, -400, 400) * s), y = (int)Math.Round(Math.Clamp(dy, -400, 400) * s);
        if (x == 0 && y == 0) return;
        Send(new List<INPUT> { Mouse(MOUSEEVENTF_MOVE, x, y) });
    }

    /// <summary>Scrollen. Natuurlijk = de inhoud volgt de vinger (zoals op de tablet zelf).</summary>
    public static void Scroll(double dx, double dy, bool natural)
    {
        var sign = natural ? 1 : -1;
        int v = (int)Math.Round(Math.Clamp(dy, -400, 400) * 4) * sign, h = (int)Math.Round(Math.Clamp(dx, -400, 400) * 4) * -sign;
        var list = new List<INPUT>();
        if (v != 0) list.Add(Mouse(MOUSEEVENTF_WHEEL, data: v));
        if (h != 0) list.Add(Mouse(MOUSEEVENTF_HWHEEL, data: h));
        Send(list);
    }

    public static void Click(bool right) => Send(new List<INPUT>
    {
        Mouse(right ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN), Mouse(right ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP),
    });

    public static void Button(bool down) => Send(new List<INPUT> { Mouse(down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP) });

    // ---------- Systeem ----------

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool LockWorkStation();

    [DllImport("user32.dll")]
    static extern IntPtr PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);

    public static void Lock()
    {
        if (!LockWorkStation()) throw new ActionException(L("Vergrendelen lukt niet"));
    }

    public static void DisplayOff() =>
        PostMessage((IntPtr)0xFFFF, 0x0112 /* WM_SYSCOMMAND */, (IntPtr)0xF170 /* SC_MONITORPOWER */, (IntPtr)2);

    // Wakker houden: SetThreadExecutionState geldt per thread, dus op de vaste UI-thread aanroepen.
    [DllImport("kernel32.dll")]
    static extern uint SetThreadExecutionState(uint flags);
    const uint ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 0x1, ES_DISPLAY_REQUIRED = 0x2;

    public static void KeepAwake(bool on) =>
        SetThreadExecutionState(on ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);

    const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    public static bool DarkMode
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
            return k?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
    }

    /// <summary>Apps én Windows zelf licht/donker wisselen, en het systeem laten weten dat het thema veranderde.</summary>
    public static void ToggleDarkMode()
    {
        var light = DarkMode ? 1 : 0;
        using (var k = Registry.CurrentUser.CreateSubKey(PersonalizeKey))
        {
            k.SetValue("AppsUseLightTheme", light, RegistryValueKind.DWord);
            k.SetValue("SystemUsesLightTheme", light, RegistryValueKind.DWord);
        }
        SendMessageTimeout((IntPtr)0xFFFF, 0x001A /* WM_SETTINGCHANGE */, IntPtr.Zero, "ImmersiveColorSet", 0x0002, 200, out _);
    }
}

sealed class ActionException : Exception
{
    public ActionException(string message) : base(message) { }
}
