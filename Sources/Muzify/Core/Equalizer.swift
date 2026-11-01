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
    /// Hệ số cân âm lượng cố định của bài (từ độ to chuẩn YouTube), 1 = giữ nguyên.
    let trackGain: Float
    /// Hệ số của limiter (1 = không giảm), chuyển mượt giữa các đoạn.
    var limiter: Float = 1

    init(gainDB: Double?) {
        // Giảm thoải mái; tăng tối đa +6 dB (phần còn lại do limiter giữ không vỡ tiếng).
        trackGain = gainDB.map { Float(pow(10, min($0, 6) / 20)) } ?? 1
    }

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
        // Tắt EQ và bài không cần cân → để nguyên âm thanh, không xử lý gì.
        guard frames > 0, (p.enabled && p.gains.contains { $0 != 0 }) || (p.normalize && trackGain != 1) else { return }
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

        let g: Float = p.normalize ? trackGain : 1
        for (i, (ptr, stride)) in chans.enumerated() where eqOn && i < setups.count {
            scratch.withUnsafeMutableBufferPointer { s in
                // Gom về mảng liền nhau → lọc → trả lại.
                vDSP_mmov(ptr, s.baseAddress!, 1, vDSP_Length(frames), vDSP_Length(stride), 1)
                delays[i].withUnsafeMutableBufferPointer { d in
                    vDSP_biquad(setups[i], d.baseAddress!, s.baseAddress!, 1, s.baseAddress!, 1, vDSP_Length(frames))
                }
                var pre = preamp
                vDSP_vsmul(s.baseAddress!, 1, &pre, s.baseAddress!, 1, vDSP_Length(frames))
                vDSP_mmov(s.baseAddress!, ptr, 1, vDSP_Length(frames), 1, vDSP_Length(stride))
            }
        }
        if g != 1 {
            for (ptr, stride) in chans {
                var gg = g
                vDSP_vsmul(ptr, stride, &gg, ptr, stride, vDSP_Length(frames))
            }
        }
        // Limiter mềm: đỉnh vượt -0,2 dBFS thì hạ nhanh, rồi nhả từ từ — thay cho cắt cứng (gây vỡ tiếng).
        var peak: Float = 0
        for (ptr, stride) in chans {
            var m: Float = 0
            vDSP_maxmgv(ptr, stride, &m, vDSP_Length(frames))
            peak = max(peak, m)
        }
        let ceiling: Float = 0.977
        let target: Float = peak * limiter > ceiling ? ceiling / max(peak, 1e-6) : min(1, limiter + (1 - limiter) * 0.08)
        let start = limiter
        limiter = min(target, peak > 0 ? ceiling / peak : 1, 1)
        if start != 1 || limiter != 1 {
            for (ptr, stride) in chans {
                var from = start
                var step = (limiter - start) / Float(frames)
                vDSP_vrampmul(ptr, stride, &from, &step, ptr, stride, vDSP_Length(frames))
                var lo: Float = -1, hi: Float = 1
                vDSP_vclip(ptr, stride, &lo, &hi, ptr, stride, vDSP_Length(frames)) // an toàn cuối cùng, hiếm khi chạm
            }
        }
    }
}

enum Equalizer {
    /// Gắn bộ xử lý vào bài vừa nạp (bỏ qua nếu không đọc được rãnh âm thanh, vd luồng HLS).
    /// `gainDB`: mức cân âm lượng của bài (nil = không cân).
    static func attach(to item: AVPlayerItem, gainDB: Double? = nil) {
        Task { @MainActor in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            let ctx = Unmanaged.passRetained(TapContext(gainDB: gainDB)).toOpaque()
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
