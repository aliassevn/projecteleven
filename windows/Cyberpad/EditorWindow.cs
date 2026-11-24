using System.Diagnostics;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>De layout-editor (shared\editor) in een eigen venster met WebView2. Het geheime editor-token gaat in de
/// #hash van de URL, zodat het nooit in een HTTP-verzoek belandt, en werkt alleen vanaf 127.0.0.1.</summary>
sealed class EditorWindow : Form
{
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly string url;

    public EditorWindow(string token)
    {
        url = $"http://127.0.0.1:{Server.Port}/editor/#mac={token}";
        Icon = TrayApp.AppIcon(32);
        Text = "Cyberpad — " + L("Layout bewerken");
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        Size = new Size(1280, 820);
        MinimumSize = new Size(900, 600);
        BackColor = Color.FromArgb(5, 6, 10);
        Controls.Add(web);
        Load += async (_, _) => await Init();
    }

    async Task Init()
    {
        try
        {
            var dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Cyberpad", "WebView2");
            var env = await CoreWebView2Environment.CreateAsync(null, dataDir);
            await web.EnsureCoreWebView2Async(env);
            var cw = web.CoreWebView2;
            cw.Settings.AreDevToolsEnabled = false;
            cw.Settings.IsStatusBarEnabled = false;
            // Alleen de editor zelf laden; links naar buiten openen in de browser.
            cw.NavigationStarting += (_, e) =>
            {
                if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var u) && u.Host == "127.0.0.1" && u.Port == Server.Port && u.AbsolutePath.StartsWith("/editor")) return;
                if (e.Uri.StartsWith("data:") || e.Uri.StartsWith("blob:")) return;
                e.Cancel = true;
                if (e.Uri.StartsWith("http")) try { Process.Start(new ProcessStartInfo(e.Uri) { UseShellExecute = true })?.Dispose(); } catch { }
            };
            cw.NewWindowRequested += (_, e) =>
            {
                e.Handled = true;
                if (e.Uri.StartsWith("http")) try { Process.Start(new ProcessStartInfo(e.Uri) { UseShellExecute = true })?.Dispose(); } catch { }
            };
            cw.Navigate(url);
        }
        catch (Exception)
        {
            // Geen WebView2 (oud Windows 10): de editor in de standaardbrowser openen. Het token werkt alleen op deze pc.
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true })?.Dispose(); } catch { }
            BeginInvoke(Close);
        }
    }

    /// <summary>Taal gewisseld: de editor herlaadt zelf (en vraagt eerst als er nog iets niet is opgeslagen).</summary>
    public void LanguageChanged()
    {
        Text = "Cyberpad — " + L("Layout bewerken");
        try { _ = web.CoreWebView2?.ExecuteScriptAsync("window.cpLanguageChanged && window.cpLanguageChanged()"); } catch { }
    }
}
