import Foundation

enum StickerInk: String, Codable, CaseIterable, Identifiable {
    case white = "White", black = "Black", silver = "Silver"
    var id: String { rawValue }
}

enum CaptionFont: String, Codable, CaseIterable, Identifiable {
    case bold = "Bold", rounded = "Rounded", serif = "Serif", mono = "Mono"
    var id: String { rawValue }
}

enum CaptionPlacement: String, Codable, CaseIterable, Identifiable {
    case top = "Top", bottom = "Bottom"
    var id: String { rawValue }
}

/// Caption center as a fraction of the sticker canvas (0...1 on each axis).
struct CaptionPosition: Codable, Equatable {
    var x: Double
    var y: Double
}

/// Looping motion rendered as a 2-second GIF. Pure math so the editor preview and the GIF frames agree.
enum StickerMotion: String, Codable, CaseIterable, Identifiable {
    case wobble = "Wobble", bounce = "Bounce", pulse = "Pulse", glitter = "Glitter"
    case spin = "Spin", float = "Float", pop = "Pop", shake = "Shake"
    var id: String { rawValue }
    static let duration: Double = 2
    static let frameRate: Double = 20

    struct Pose { var rotation = 0.0; var scale = 1.0; var offsetY = 0.0; var offsetX = 0.0 }
    struct Sparkle { var x: Double; var y: Double; var size: Double; var alpha: Double }

    /// Subject transform at phase `t` in 0..<1 (rotation in degrees, offset in 512-point canvas units).
    func pose(at t: Double) -> Pose {
        let wave = sin(2 * .pi * t)
        switch self {
        case .wobble: return Pose(rotation: 7 * wave)
        case .bounce: return Pose(offsetY: -22 * abs(wave))
        case .pulse: return Pose(scale: 1 + 0.06 * wave)
        case .glitter: return Pose()
        case .spin: return Pose(rotation: 360 * t)
        case .float: return Pose(offsetY: 12 * wave, offsetX: 6 * cos(2 * .pi * t))
        case .pop: return Pose(scale: 1 - 0.15 * (0.5 + 0.5 * cos(2 * .pi * t)))
        case .shake: return Pose(offsetX: 8 * sin(8 * .pi * t))
        }
    }

    /// Twinkling sparkles in normalized canvas coordinates. Positions are fixed; alpha cycles per sparkle.
    func sparkles(at t: Double) -> [Sparkle] {
        guard self == .glitter else { return [] }
        return Self.sparkleSeeds.map { seed in
            let twinkle = max(0, sin(2 * .pi * (t + seed.phase)))
            return Sparkle(x: seed.x, y: seed.y, size: seed.size, alpha: twinkle * twinkle)
        }
    }
    private static let sparkleSeeds: [(x: Double, y: Double, size: Double, phase: Double)] = {
        var state: UInt32 = 2_463_534_242
        func next() -> Double { state = state &* 1_664_525 &+ 1_013_904_223; return Double(state >> 8) / Double(1 << 24) }
        return (0..<14).map { _ in (x: 0.18 + 0.64 * next(), y: 0.18 + 0.64 * next(), size: 10 + 14 * next(), phase: next()) }
    }()
}

enum StickerPlayback: String, Codable, CaseIterable, Identifiable {
    case loop = "Loop", reverse = "Reverse", pingPong = "Back & forth"
    var id: String { rawValue }
}

enum StickerOutput: String, Codable, CaseIterable, Identifiable {
    case png = "Still PNG", gif = "Animated GIF"
    var id: String { rawValue }
}

struct StickerAnimationSettings: Codable, Equatable {
    var duration: Double = 2
    var framesPerSecond = 20
    var playback: StickerPlayback = .loop
    var safeDuration: Double { min(2, max(0.5, duration.isFinite ? duration : 2)) }
    var safeFPS: Int { framesPerSecond == 15 ? 15 : 20 }
    var frameCount: Int { max(1, Int((safeDuration * Double(safeFPS)).rounded())) }
    func phase(_ value: Double) -> Double {
        let t = value - floor(value)
        switch playback {
        case .loop: return t
        case .reverse: return 1 - t
        case .pingPong: return t < 0.5 ? 2 * t : 2 - 2 * t
        }
    }
}

struct StickerAppearance: Codable, Equatable {
    var removesBackground = true
    var outlineWidth: Double = 8
    var outlineColor: StickerInk = .white
    var shadow = false
    var flipped = false
    var captionFont: CaptionFont = .bold
    var captionSize: Double = 36
    var captionColor: StickerInk = .black
    var captionPlacement: CaptionPlacement = .bottom
    // Free placement; nil falls back to captionPlacement so older stickers decode unchanged.
    var captionPosition: CaptionPosition?
    var motion: StickerMotion?
    // Optional additions decode older libraries without changing their output.
    var animationSettings: StickerAnimationSettings?
    var output: StickerOutput?
    var outlineHex: String?
    var captionHex: String?
    var animation: StickerAnimationSettings { animationSettings ?? StickerAnimationSettings() }
    var resolvedOutput: StickerOutput { output ?? (motion == nil ? .png : .gif) }

    // Older stickers keep their original rendering until explicitly edited.
    static var legacy: StickerAppearance {
        var value = StickerAppearance()
        value.removesBackground = false
        value.outlineWidth = 0
        return value
    }
}
