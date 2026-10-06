import Accelerate
import AVFoundation
import MediaToolbox

// MARK: - Cài đặt âm thanh

@MainActor
final class AudioSettings: ObservableObject {
    static let shared = AudioSettings()
    private let d = UserDefaults.standard

    nonisolated static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    enum Preset: String, CaseIterable, Identifiable {
        case flat, bassBoost, bassReducer, trebleBoost, vocal, pop, rock, electronic, acoustic, lateNight
        var id: String { rawValue }

        var title: String {
            switch self {
            case .flat: L("Phẳng")
            case .bassBoost: L("Tăng bass")
            case .bassReducer: L("Giảm bass")
            case .trebleBoost: L("Tăng treble")
            case .vocal: L("Giọng hát")
            case .pop: "Pop"
            case .rock: "Rock"
            case .electronic: L("Điện tử")
            case .acoustic: "Acoustic"
            case .lateNight: L("Đêm khuya")
            }
        }

        var gains: [Float] {
            switch self {
            case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            case .bassBoost: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0]
            case .bassReducer: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0]
            case .trebleBoost: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]
            case .vocal: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]
            case .pop: [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2]
            case .rock: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]
            case .electronic: [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]
            case .acoustic: [4, 4, 3, 1, 2, 2, 3, 3, 3, 2]
            case .lateNight: [-3, -2, 0, 1, 2, 2, 1, 0, -2, -3]
            }
        }
    }

    @Published var eqEnabled: Bool { didSet { d.set(eqEnabled, forKey: "eqEnabled"); push() } }
    @Published var gains: [Float] { didSet { d.set(gains, forKey: "eqGains"); push() } }
    /// Tự cân âm lượng giữa các bài (bài to thì nhỏ lại, bài nhỏ thì to lên).
    @Published var normalize: Bool { didSet { d.set(normalize, forKey: "normalize"); push() } }
    /// Bỏ qua đoạn không phải nhạc (SponsorBlock).
    @Published var skipNonMusic: Bool { didSet { d.set(skipNonMusic, forKey: "skipNonMusic") } }

    var preset: Preset? { Preset.allCases.first { $0.gains == gains } }

    private init() {
        eqEnabled = d.bool(forKey: "eqEnabled")
        gains = (d.array(forKey: "eqGains") as? [Float]).flatMap { $0.count == 10 ? $0 : nil } ?? Array(repeating: 0, count: 10)
        normalize = d.object(forKey: "normalize") as? Bool ?? true
        skipNonMusic = d.object(forKey: "skipNonMusic") as? Bool ?? true
        push()
    }

    func apply(_ p: Preset) { gains = p.gains }

    private func push() { EQParams.shared.update(enabled: eqEnabled, gains: gains, normalize: normalize) }
}

/// Bản sao tham số cho luồng âm thanh (đọc trong callback, có khoá).
final class EQParams: @unchecked Sendable {
    static let shared = EQParams()
    private let lock = NSLock()
    private var enabled = false
    private var gains: [Float] = Array(repeating: 0, count: 10)
    private var normalize = true
    private(set) var version = 0

    func update(enabled: Bool, gains: [Float], normalize: Bool) {
        lock.lock()
        self.enabled = enabled; self.gains = gains; self.normalize = normalize; version += 1
        lock.unlock()
    }

    func snapshot() -> (enabled: Bool, gains: [Float], normalize: Bool, version: Int) {
        lock.lock(); defer { lock.unlock() }
        return (enabled, gains, normalize, version)
    }
}

// MARK: - Bộ xử lý (MTAudioProcessingTap gắn vào AVPlayerItem)

/// Mỗi bài một bộ: 10 bộ lọc peaking (biquad) cho mỗi kênh + tự cân âm lượng + chặn vỡ tiếng.
private final class TapContext {
    var sampleRate: Double = 44100
    var channels = 2
    var interleaved = false
    var setups: [vDSP_biquad_Setup] = []
    var delays: [[Float]] = []
    var version = -1
    var eqOn = false
    var preamp: Float = 1
    var scratch: [Float] = []
    var level: Float = 0.1
    var gain: Float = 1

    deinit { setups.forEach(vDSP_biquad_DestroySetup) }

    func prepare(_ f: AudioStreamBasicDescription, maxFrames: Int) {
        sampleRate = f.mSampleRate
        interleaved = f.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        channels = Int(f.mChannelsPerFrame)
        scratch = [Float](repeating: 0, count: max(maxFrames, 4096))
        version = -1
    }

    private func rebuild(_ gains: [Float]) {
        setups.forEach(vDSP_biquad_DestroySetup)
        setups = []
        var coeffs: [Double] = []
        for (f, g) in zip(AudioSettings.frequencies, gains) where Double(f) < sampleRate / 2 {
            // Bộ lọc peaking theo RBJ Audio EQ Cookbook, Q = 1.41.
            let a = pow(10, Double(g) / 40), w = 2 * Double.pi * Double(f) / sampleRate
            let alpha = sin(w) / (2 * 1.41), c = cos(w)
            let a0 = 1 + alpha / a
            coeffs += [(1 + alpha * a) / a0, -2 * c / a0, (1 - alpha * a) / a0, -2 * c / a0, (1 - alpha / a) / a0]
        }
        let sections = coeffs.count / 5
        for _ in 0..<channels {
            if let s = vDSP_biquad_CreateSetup(coeffs, vDSP_Length(sections)) { setups.append(s) }
        }
        delays = Array(repeating: [Float](repeating: 0, count: 2 * sections + 2), count: channels)
        // Chừa khoảng trống để dải được tăng không làm vỡ tiếng.
        preamp = pow(10, -max(gains.max() ?? 0, 0) / 20)
    }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) {
        let p = EQParams.shared.snapshot()
        guard p.enabled || p.normalize, frames > 0 else { return }
        if p.version != version {
            version = p.version
            eqOn = p.enabled && p.gains.contains { $0 != 0 }
            if eqOn { rebuild(p.gains) }
        }
        if scratch.count < frames { scratch = [Float](repeating: 0, count: frames) }

        // Danh sách (con trỏ, bước nhảy) cho từng kênh.
        var chans: [(UnsafeMutablePointer<Float>, Int)] = []
        for buf in abl {
            guard let data = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let n = Int(buf.mNumberChannels)
            for c in 0..<n { chans.append((data + c, n)) }
        }

        var sumSquares: Float = 0
        for (i, (ptr, stride)) in chans.enumerated() {
            scratch.withUnsafeMutableBufferPointer { s in
                // Gom về mảng liền nhau → lọc → trả lại.
                vDSP_mmov(ptr, s.baseAddress!, 1, vDSP_Length(frames), vDSP_Length(stride), 1)
                if eqOn, i < setups.count {
                    delays[i].withUnsafeMutableBufferPointer { d in
                        vDSP_biquad(setups[i], d.baseAddress!, s.baseAddress!, 1, s.baseAddress!, 1, vDSP_Length(frames))
                    }
                    var pre = preamp
                    vDSP_vsmul(s.baseAddress!, 1, &pre, s.baseAddress!, 1, vDSP_Length(frames))
                }
                var ss: Float = 0
                vDSP_svesq(s.baseAddress!, 1, &ss, vDSP_Length(frames))
                sumSquares += ss
                vDSP_mmov(s.baseAddress!, ptr, 1, vDSP_Length(frames), 1, vDSP_Length(stride))
            }
        }

        // Tự cân âm lượng: theo dõi độ to trung bình (chậm), kéo về khoảng -20 dBFS.
        var g: Float = 1
        if p.normalize, !chans.isEmpty {
            let rms = sqrt(sumSquares / Float(frames * chans.count))
            if rms > 0.0005 { level = level * 0.97 + rms * 0.03 }
            let target = min(max(0.1 / max(level, 0.001), 0.5), 2.5)
            gain += (target - gain) * 0.05
            g = gain
        }
        for (ptr, stride) in chans {
            var gg = g, lo: Float = -1, hi: Float = 1
            if g != 1 { vDSP_vsmul(ptr, stride, &gg, ptr, stride, vDSP_Length(frames)) }
            vDSP_vclip(ptr, stride, &lo, &hi, ptr, stride, vDSP_Length(frames))
        }
    }
}

enum Equalizer {
    /// Gắn bộ xử lý vào bài vừa nạp (bỏ qua nếu không đọc được rãnh âm thanh, vd luồng HLS).
    static func attach(to item: AVPlayerItem) {
        Task { @MainActor in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            let ctx = Unmanaged.passRetained(TapContext()).toOpaque()
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: ctx,
                init: { _, info, storage in storage.pointee = info },
                finalize: { tap in Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
                prepare: { tap, maxFrames, format in
                    Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                        .prepare(format.pointee, maxFrames: Int(maxFrames))
                },
                unprepare: nil,
                process: { tap, frames, _, bufferList, framesOut, flagsOut in
                    guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                    Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                        .process(UnsafeMutableAudioBufferListPointer(bufferList), frames: Int(framesOut.pointee))
                })
            var unmanaged: Unmanaged<MTAudioProcessingTap>?
            guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &unmanaged) == noErr,
                  let tap = unmanaged?.takeRetainedValue() else {
                Unmanaged<TapContext>.fromOpaque(ctx).release()
                return
            }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            item.audioMix = mix
        }
    }
}
