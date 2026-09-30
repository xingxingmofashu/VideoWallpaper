import AVFoundation
import Accelerate
import MediaToolbox
import Foundation
import Darwin
import Synchronization

final class AudioSpectrum {
    static let bandCount = 48

    private static let fftSize = 2048
    private static let ringCapacity = 16384
    private static let minFrequency: Float = 45
    private static let maxFrequency: Float = 15000
    private static let floorDecibels: Float = -78
    private static let dynamicRangeDecibels: Float = 40
    private static let responseCurve: Float = 1.25
    private static let maximumCeilingDecibels: Float = -6
    private static let springOmega: Float = 17
    private static let subSteps = 4
    private static let peakFall: Float = 0.012
    private static let peakHoldFrames = 18

    private var lock = os_unfair_lock_s()
    private var pending = [Float](repeating: 0, count: AudioSpectrum.fftSize * 2)
    private var pendingCount = 0
    private var ring = [Float](repeating: 0, count: AudioSpectrum.ringCapacity)
    private var ringWrite = 0
    private var filled = 0
    private var scratch = [Float](repeating: 0, count: AudioSpectrum.fftSize)

    private let sampleRate = Atomic<Float>(0)
    private var bandRanges: [(Int, Int)] = []

    private var fftSetup: vDSP_DFT_Setup?
    private var window = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    private var fftReal = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    private var fftImag = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    private var outReal = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    private var outImag = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    private var magnitudes = [Float](repeating: 0, count: AudioSpectrum.fftSize / 2)

    private var values = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var velocities = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var targets = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var smoothed = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var peaks = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var peakHold = [Int](repeating: 0, count: AudioSpectrum.bandCount)
    private var adaptiveMax: Float = 0.0001

    private var taps: [ObjectIdentifier: MTAudioProcessingTap] = [:]

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(AudioSpectrum.fftSize), .FORWARD)
        vDSP_hann_window(&window, vDSP_Length(AudioSpectrum.fftSize), Int32(vDSP_HANN_NORM))
    }

    func attach(to item: AVPlayerItem, hasAudio: @escaping (Bool) -> Void) {
        let key = ObjectIdentifier(item)
        item.asset.loadTracks(withMediaType: .audio) { [weak self] tracks, _ in
            guard let self, let track = tracks?.first else {
                DispatchQueue.main.async { hasAudio(false) }
                return
            }
            var tap: MTAudioProcessingTap?
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: Unmanaged.passUnretained(self).toOpaque(),
                init: audioSpectrumTapInit,
                finalize: audioSpectrumTapFinalize,
                prepare: audioSpectrumTapPrepare,
                unprepare: audioSpectrumTapUnprepare,
                process: audioSpectrumTapProcess)
            guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
                  let tap else {
                DispatchQueue.main.async { hasAudio(false) }
                return
            }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            DispatchQueue.main.async {
                item.audioMix = mix
                self.taps[key] = tap
                hasAudio(true)
            }
        }
    }

    func detach(from item: AVPlayerItem) {
        item.audioMix = nil
        taps[ObjectIdentifier(item)] = nil
    }

    func prepare(sampleRate rate: Float) {
        sampleRate.store(rate, ordering: .relaxed)
    }

    func ingest(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard frames > 0, !buffers.isEmpty else { return }
        let limit = min(frames, pending.count)

        os_unfair_lock_lock(&lock)
        var written = 0
        if buffers.count >= 2,
           let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            for index in 0..<limit {
                pending[index] = (left[index] + right[index]) * 0.5
            }
            written = limit
        } else if let raw = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
            let channels = max(1, Int(buffers[0].mNumberChannels))
            if channels == 1 {
                for index in 0..<limit {
                    pending[index] = raw[index]
                }
            } else {
                for index in 0..<limit {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += raw[index * channels + channel]
                    }
                    pending[index] = sum / Float(channels)
                }
            }
            written = limit
        }
        pendingCount = written
        os_unfair_lock_unlock(&lock)
    }

    func advance(active: Bool) -> ([Float], [Float]) {
        let rate = sampleRate.load(ordering: .relaxed)
        if bandRanges.isEmpty, rate > 0 {
            buildBandRanges(sampleRate: rate)
        }
        guard let fftSetup, !bandRanges.isEmpty else {
            return (values, peaks)
        }

        os_unfair_lock_lock(&lock)
        if pendingCount > 0 {
            for index in 0..<pendingCount {
                ring[ringWrite] = pending[index]
                ringWrite = (ringWrite + 1) % ring.count
            }
            filled = min(filled + pendingCount, AudioSpectrum.fftSize)
            pendingCount = 0
        }
        if filled >= AudioSpectrum.fftSize {
            for index in 0..<AudioSpectrum.fftSize {
                let position = (ringWrite - AudioSpectrum.fftSize + index + ring.count) % ring.count
                scratch[index] = ring[position]
            }
        }
        os_unfair_lock_unlock(&lock)

        if filled >= AudioSpectrum.fftSize {
            analyse(fftSetup)
        }
        stepSprings(active: active)
        return (values, peaks)
    }

    private func analyse(_ setup: vDSP_DFT_Setup) {
        let size = AudioSpectrum.fftSize
        vDSP_vmul(scratch, 1, window, 1, &fftReal, 1, vDSP_Length(size))
        vDSP_DFT_Execute(setup, fftReal, fftImag, &outReal, &outImag)

        let binCount = size / 2
        let normalisation = 2 / Float(size)
        for bin in 0..<binCount {
            let real = outReal[bin]
            let imaginary = outImag[bin]
            magnitudes[bin] = (real * real + imaginary * imaginary).squareRoot() * normalisation
        }

        var loudest: Float = 0
        for index in 0..<AudioSpectrum.bandCount {
            let range = bandRanges[index]
            var peak: Float = 0
            for bin in range.0..<range.1 {
                peak = max(peak, magnitudes[bin])
            }
            loudest = max(loudest, peak)
            targets[index] = 20 * log10f(peak + 1e-7)
        }

        if loudest > adaptiveMax {
            adaptiveMax += (loudest - adaptiveMax) * 0.5
        } else {
            adaptiveMax *= 0.99
        }
        let ceiling = min(
            max(20 * log10f(adaptiveMax), AudioSpectrum.floorDecibels + AudioSpectrum.dynamicRangeDecibels),
            AudioSpectrum.maximumCeilingDecibels)
        let reference = max(ceiling - AudioSpectrum.dynamicRangeDecibels, AudioSpectrum.floorDecibels)

        for index in 0..<AudioSpectrum.bandCount {
            let normalised = max((targets[index] - reference) / (ceiling - reference), 0)
            targets[index] = min(powf(normalised, AudioSpectrum.responseCurve), 1)
        }

        var targetMax: Float = 0
        for value in targets {
            targetMax = max(targetMax, value)
        }
        var smoothedMax: Float = 0
        for index in 0..<AudioSpectrum.bandCount {
            let previous = index > 0 ? targets[index - 1] : targets[index]
            let next = index < AudioSpectrum.bandCount - 1 ? targets[index + 1] : targets[index]
            let value = previous * 0.25 + targets[index] * 0.5 + next * 0.25
            smoothed[index] = value
            smoothedMax = max(smoothedMax, value)
        }
        if smoothedMax > 0.0001, targetMax > smoothedMax {
            let factor = targetMax / smoothedMax
            for index in 0..<AudioSpectrum.bandCount {
                smoothed[index] = min(smoothed[index] * factor, 1)
            }
        }
    }

    private func stepSprings(active: Bool) {
        let step = (1.0 / 30.0) / Float(AudioSpectrum.subSteps)
        for index in 0..<AudioSpectrum.bandCount {
            let goal = active ? smoothed[index] : 0
            var value = values[index]
            var velocity = velocities[index]
            for _ in 0..<AudioSpectrum.subSteps {
                let acceleration = AudioSpectrum.springOmega * AudioSpectrum.springOmega * (goal - value)
                    - 2 * AudioSpectrum.springOmega * velocity
                velocity += acceleration * step
                value += velocity * step
            }
            value = min(max(value, 0), 1.2)
            values[index] = value
            velocities[index] = velocity

            if value >= peaks[index] {
                peaks[index] = value
                peakHold[index] = AudioSpectrum.peakHoldFrames
            } else if peakHold[index] > 0 {
                peakHold[index] -= 1
            } else {
                peaks[index] = max(value, peaks[index] - AudioSpectrum.peakFall)
            }
        }
    }

    private func buildBandRanges(sampleRate rate: Float) {
        let binCount = AudioSpectrum.fftSize / 2
        let nyquist = rate / 2
        let ratio = AudioSpectrum.maxFrequency / AudioSpectrum.minFrequency
        bandRanges = (0..<AudioSpectrum.bandCount).map { index in
            let lower = AudioSpectrum.minFrequency * powf(ratio, Float(index) / Float(AudioSpectrum.bandCount))
            let upper = AudioSpectrum.minFrequency * powf(ratio, Float(index + 1) / Float(AudioSpectrum.bandCount))
            let lowBin = max(1, Int(lower / nyquist * Float(binCount)))
            let highBin = max(lowBin + 1, Int(upper / nyquist * Float(binCount)))
            return (min(lowBin, binCount - 1), min(highBin, binCount))
        }
    }
}

private func audioSpectrumTapInit(_ tap: MTAudioProcessingTap, _ clientInfo: UnsafeMutableRawPointer?, _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func audioSpectrumTapFinalize(_ tap: MTAudioProcessingTap) {}

private func audioSpectrumTapPrepare(_ tap: MTAudioProcessingTap, _ maxFrames: CMItemCount, _ format: UnsafePointer<AudioStreamBasicDescription>) {
    let spectrum = Unmanaged<AudioSpectrum>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    spectrum.prepare(sampleRate: Float(format.pointee.mSampleRate))
}

private func audioSpectrumTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func audioSpectrumTapProcess(_ tap: MTAudioProcessingTap, _ numberFrames: CMItemCount, _ flags: MTAudioProcessingTapFlags, _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>, _ numberFramesOut: UnsafeMutablePointer<CMItemCount>, _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    guard MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut) == noErr else {
        numberFramesOut.pointee = 0
        return
    }
    let spectrum = Unmanaged<AudioSpectrum>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    spectrum.ingest(bufferListInOut, frames: Int(numberFramesOut.pointee))
}
