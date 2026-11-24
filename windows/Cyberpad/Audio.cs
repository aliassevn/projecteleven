using System.Runtime.InteropServices;

namespace Cyberpad;

/// <summary>Volume en dempen van luidspreker en microfoon via Core Audio (IAudioEndpointVolume).</summary>
static class Audio
{
    const int eRender = 0, eCapture = 1, eConsole = 0, eCommunications = 2;
    const int CLSCTX_ALL = 23;

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorCom { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float levelDB, ref Guid ctx);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
        [PreserveSig] int GetMasterVolumeLevel(out float levelDB);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDB, ref Guid ctx);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid ctx);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDB);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    static Guid ctx = Guid.Empty;

    static IAudioEndpointVolume? Endpoint(bool mic)
    {
        try
        {
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            if (en.GetDefaultAudioEndpoint(mic ? eCapture : eRender, mic ? eCommunications : eConsole, out var dev) != 0 || dev == null)
            {
                if (!mic || en.GetDefaultAudioEndpoint(eCapture, eConsole, out dev) != 0 || dev == null) return null;
            }
            var iid = typeof(IAudioEndpointVolume).GUID;
            if (dev.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out var o) != 0) return null;
            return o as IAudioEndpointVolume;
        }
        catch { return null; }
    }

    public static float? Volume(bool mic = false)
    {
        var e = Endpoint(mic);
        return e != null && e.GetMasterVolumeLevelScalar(out var v) == 0 ? v : null;
    }

    public static bool? Muted(bool mic = false)
    {
        var e = Endpoint(mic);
        return e != null && e.GetMute(out var m) == 0 ? m : null;
    }

    public static void SetVolume(float v, bool mic = false)
    {
        var e = Endpoint(mic) ?? throw new ActionException((mic ? I18n.L("Geen microfoon gevonden") : I18n.L("Geen geluidsuitgang gevonden")));
        e.SetMasterVolumeLevelScalar(Math.Clamp(v, 0f, 1f), ref ctx);
        if (!mic && v > 0) e.SetMute(false, ref ctx);
    }

    public static void ChangeVolume(float by, bool mic = false) => SetVolume((Volume(mic) ?? 0) + by, mic);

    public static void ToggleMute(bool mic = false)
    {
        var e = Endpoint(mic) ?? throw new ActionException((mic ? I18n.L("Geen microfoon gevonden") : I18n.L("Geen geluidsuitgang gevonden")));
        e.GetMute(out var m);
        e.SetMute(!m, ref ctx);
    }
}
