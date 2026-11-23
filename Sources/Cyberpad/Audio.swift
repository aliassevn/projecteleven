import Foundation
import CoreAudio

/// Volume, geluid uit en microfoon uit via CoreAudio (geen extra rechten nodig).
final class AudioController {
    private var savedMicVolume: Float32?

    // MARK: Uitvoer

    var volume: Float32? {
        guard let dev = device(input: false) else { return nil }
        let vals = volumeElements(dev, input: false).compactMap { getFloat(dev, kAudioDevicePropertyVolumeScalar, input: false, element: $0) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Float32(vals.count)
    }

    func setVolume(_ v: Float32) {
        guard let dev = device(input: false) else { return }
        let clamped = min(max(v, 0), 1)
        for el in volumeElements(dev, input: false) {
            setFloat(dev, kAudioDevicePropertyVolumeScalar, input: false, element: el, value: clamped)
        }
        if clamped > 0, muted == true { setMuted(false) }
    }

    func changeVolume(by delta: Float32) {
        setVolume((volume ?? 0.5) + delta)
    }

    var muted: Bool? {
        guard let dev = device(input: false),
              let v = getUInt32(dev, kAudioDevicePropertyMute, input: false) else { return nil }
        return v != 0
    }

    func setMuted(_ m: Bool) {
        guard let dev = device(input: false) else { return }
        setUInt32(dev, kAudioDevicePropertyMute, input: false, value: m ? 1 : 0)
    }

    func toggleMute() { setMuted(!(muted ?? false)) }

    // MARK: Microfoon

    var micMuted: Bool {
        guard let dev = device(input: true) else { return false }
        if isSettable(dev, kAudioDevicePropertyMute, input: true, element: kAudioObjectPropertyElementMain),
           let v = getUInt32(dev, kAudioDevicePropertyMute, input: true) {
            return v != 0
        }
        return savedMicVolume != nil
    }

    func toggleMic() {
        guard let dev = device(input: true) else { return }
        // Liefst echte mute; sommige microfoons kennen dat niet, dan volume naar 0 en terug.
        if isSettable(dev, kAudioDevicePropertyMute, input: true, element: kAudioObjectPropertyElementMain) {
            setUInt32(dev, kAudioDevicePropertyMute, input: true, value: micMuted ? 0 : 1)
            return
        }
        let els = volumeElements(dev, input: true)
        if let saved = savedMicVolume {
            els.forEach { setFloat(dev, kAudioDevicePropertyVolumeScalar, input: true, element: $0, value: saved) }
            savedMicVolume = nil
        } else {
            let cur = els.compactMap { getFloat(dev, kAudioDevicePropertyVolumeScalar, input: true, element: $0) }.first ?? 0.7
            savedMicVolume = cur > 0 ? cur : 0.7
            els.forEach { setFloat(dev, kAudioDevicePropertyVolumeScalar, input: true, element: $0, value: 0) }
        }
    }

    // MARK: CoreAudio-hulpjes

    private func device(input: Bool) -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return st == noErr && id != 0 ? id : nil
    }

    private func address(_ sel: AudioObjectPropertySelector, input: Bool, element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel,
                                   mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    /// Hoofdkanaal als dat instelbaar is, anders de losse kanalen 1 en 2.
    private func volumeElements(_ dev: AudioDeviceID, input: Bool) -> [UInt32] {
        if isSettable(dev, kAudioDevicePropertyVolumeScalar, input: input, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { isSettable(dev, kAudioDevicePropertyVolumeScalar, input: input, element: $0) }
    }

    private func isSettable(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector, input: Bool, element: UInt32) -> Bool {
        var addr = address(sel, input: input, element: element)
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr && settable.boolValue
    }

    private func getFloat(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector, input: Bool, element: UInt32) -> Float32? {
        var addr = address(sel, input: input, element: element)
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private func setFloat(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector, input: Bool, element: UInt32, value: Float32) {
        var addr = address(sel, input: input, element: element)
        var v = value
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    private func getUInt32(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector, input: Bool) -> UInt32? {
        var addr = address(sel, input: input, element: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private func setUInt32(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector, input: Bool, value: UInt32) {
        var addr = address(sel, input: input, element: kAudioObjectPropertyElementMain)
        var v = value
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}
