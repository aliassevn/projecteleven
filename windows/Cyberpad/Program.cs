using static Cyberpad.I18n;

namespace Cyberpad;

static class Program
{
    static SynchronizationContext? ui;

    /// <summary>Iets op de vaste UI-thread uitvoeren (vensters, wakker houden).</summary>
    public static void OnUi(Action a)
    {
        if (ui == null) { a(); return; }
        ui.Post(_ => { try { a(); } catch { } }, null);
    }

    [STAThread]
    static void Main()
    {
        using var mutex = new Mutex(true, "ProjectEleven.Cyberpad", out var first);
        Paths.Ensure();
        I18n.Load();
        if (!first)
        {
            MessageBox.Show(L("Cyberpad draait al. Je vindt het icoon rechtsonder in het systeemvak."), "Cyberpad",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        ui = new WindowsFormsSynchronizationContext();
        SynchronizationContext.SetSynchronizationContext(ui);

        var core = new Core();
        var tray = new TrayApp(core);
        _ = core.StartAsync().ContinueWith(_ => OnUi(tray.ServerStarted));
        Application.Run(tray);
        core.Server.StopAsync().Wait(2000);
    }
}
