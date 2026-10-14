import UIKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

@MainActor
protocol StickerClipboard {
    func copy(_ image: UIImage) throws
    func copy(gif: Data, fallback: UIImage) throws
}

extension StickerClipboard {
    func copy(gif: Data, fallback: UIImage) throws { try copy(fallback) }
}

struct SystemStickerClipboard: StickerClipboard {
    func copy(_ image: UIImage) throws {
        guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func copy(gif: Data, fallback: UIImage) throws {
        guard let png = fallback.pngData() else { throw CocoaError(.fileWriteUnknown) }
        // One item with both representations: apps that take GIFs animate it, others get the PNG.
        UIPasteboard.general.setItems([[UTType.gif.identifier: gif, UTType.png.identifier: png]])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

enum StickerImageService {
    nonisolated static func downsample(_ data: Data, maxPixelSize: Int = 1024) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Bulk import: first frame (downsampled), whether the data is a multi-frame GIF, and whether it already has see-through pixels.
    nonisolated static func decodeImport(_ data: Data) -> (image: UIImage, isAnimatedGIF: Bool, hasTransparency: Bool)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = downsample(data) else { return nil }
        let isGIF = (CGImageSourceGetType(source) as String?) == UTType.gif.identifier && CGImageSourceGetCount(source) > 1
        return (image, isGIF, hasTransparency(image))
    }

    /// True when any pixel of a 32×32 reduction is noticeably transparent. Screenshots carry an alpha channel but stay opaque.
    nonisolated static func hasTransparency(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }

    private static let renderContext = CIContext()
    private static let canvas: UIGraphicsImageRenderer = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
    }()

    static func color(_ ink: StickerInk) -> UIColor {
        switch ink {
        case .white: .white
        case .black: .black
        case .silver: UIColor(white: 0.65, alpha: 1)
        }
    }

    static func color(_ ink: StickerInk, hex: String?) -> UIColor {
        guard let hex, hex.count == 7, hex.first == "#", let rgb = UInt32(hex.dropFirst(), radix: 16) else { return color(ink) }
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    static func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
    private static func contrastingStroke(for color: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return red * 0.2126 + green * 0.7152 + blue * 0.0722 < 0.5 ? .white : .black
    }

    static func render(source: UIImage, caption: String, scale: Double, rotation: Double,
                       appearance: StickerAppearance = .legacy) -> UIImage {
        let outlined = outlinedSubject(source: source, scale: scale, rotation: rotation, appearance: appearance)
        return compose(outlined, caption: caption, appearance: appearance, phase: nil)
    }

    /// Frames for the motion loop; the outlined subject is built once and only transformed per frame.
    static func renderFrames(source: UIImage, caption: String, scale: Double, rotation: Double,
                             appearance: StickerAppearance) -> [UIImage] {
        guard appearance.motion != nil else { return [] }
        let outlined = outlinedSubject(source: source, scale: scale, rotation: rotation, appearance: appearance)
        let count = appearance.animation.frameCount
        return (0..<count).map { compose(outlined, caption: caption, appearance: appearance, phase: Double($0) / Double(count)) }
    }

    static func gifData(frames: [UIImage], framesPerSecond: Int = 20) -> Data? {
        let data = NSMutableData()
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = 1.0 / Double(framesPerSecond == 15 ? 15 : 20)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                               kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for frame in frames {
            guard let cgImage = frame.cgImage else { return nil }
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func outlinedSubject(source: UIImage, scale: Double, rotation: Double, appearance: StickerAppearance) -> UIImage {
        let layer = canvas.image { context in
            let available = CGSize(width: 350, height: 350)
            let radians = rotation * .pi / 180
            // Fit the rotated bounds too, leaving room for the outline and shadow.
            let rotatedWidth = abs(source.size.width * cos(radians)) + abs(source.size.height * sin(radians))
            let rotatedHeight = abs(source.size.width * sin(radians)) + abs(source.size.height * cos(radians))
            let factor = min(available.width / max(rotatedWidth, 1), available.height / max(rotatedHeight, 1)) * scale
            let size = CGSize(width: source.size.width * factor, height: source.size.height * factor)
            let cg = context.cgContext
            cg.translateBy(x: 256, y: 256)
            cg.rotate(by: radians)
            cg.scaleBy(x: appearance.flipped ? -1 : 1, y: 1)
            source.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
        return addOutline(layer, width: appearance.outlineWidth, color: color(appearance.outlineColor, hex: appearance.outlineHex))
    }

    static func compose(_ outlined: UIImage, caption: String, appearance: StickerAppearance, phase: Double?) -> UIImage {
        canvas.image { context in
            let cg = context.cgContext
            cg.saveGState()
            if let phase, let motion = appearance.motion {
                let pose = motion.pose(at: appearance.animation.phase(phase))
                cg.translateBy(x: 256 + pose.offsetX, y: 256 + pose.offsetY)
                cg.rotate(by: pose.rotation * .pi / 180)
                cg.scaleBy(x: pose.scale, y: pose.scale)
                cg.translateBy(x: -256, y: -256)
            }
            if appearance.shadow { cg.setShadow(offset: CGSize(width: 0, height: 5), blur: 8, color: UIColor.black.withAlphaComponent(0.3).cgColor) }
            outlined.draw(at: .zero)
            cg.restoreGState()
            if let phase, let motion = appearance.motion {
                for sparkle in motion.sparkles(at: appearance.animation.phase(phase)) where sparkle.alpha > 0.02 {
                    drawSparkle(cg, at: CGPoint(x: sparkle.x * 512, y: sparkle.y * 512), size: sparkle.size, alpha: sparkle.alpha)
                }
            }
            guard let layout = captionLayout(caption, appearance: appearance) else { return }
            (caption as NSString).draw(with: layout.rect, options: .usesLineFragmentOrigin, attributes: layout.attributes, context: nil)
        }
    }

    /// Four-point star. Shared shape for GIF frames and the editor preview.
    static func sparklePath(at center: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<8 {
            let radius = index.isMultiple(of: 2) ? size : size * 0.28
            let angle = CGFloat(index) * .pi / 4 - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func drawSparkle(_ cg: CGContext, at center: CGPoint, size: CGFloat, alpha: Double) {
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.addPath(sparklePath(at: center, size: size))
        cg.setFillColor(UIColor.white.cgColor)
        cg.setStrokeColor(UIColor(white: 0.65, alpha: 1).cgColor)
        cg.setLineWidth(1)
        cg.drawPath(using: .fillStroke)
        cg.restoreGState()
    }

    /// Caption center in the 512-point sticker canvas.
    static func captionCenter(_ appearance: StickerAppearance) -> CGPoint {
        if let position = appearance.captionPosition { return CGPoint(x: position.x * 512, y: position.y * 512) }
        return CGPoint(x: 256, y: appearance.captionPlacement == .bottom ? 448 : 64)
    }

    /// Text attributes and the rect the caption occupies in the 512-point canvas, clamped inside it.
    static func captionLayout(_ caption: String, appearance: StickerAppearance) -> (attributes: [NSAttributedString.Key: Any], rect: CGRect)? {
        guard !caption.isEmpty else { return nil }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var pointSize = appearance.captionSize
        func attributes() -> [NSAttributedString.Key: Any] {
            var font = UIFont.systemFont(ofSize: pointSize, weight: .bold)
            let design: UIFontDescriptor.SystemDesign = appearance.captionFont == .rounded ? .rounded : appearance.captionFont == .mono ? .monospaced : .serif
            if appearance.captionFont != .bold, let descriptor = font.fontDescriptor.withDesign(design) {
                font = UIFont(descriptor: descriptor, size: pointSize)
            }
            return [.font: font, .foregroundColor: color(appearance.captionColor, hex: appearance.captionHex),
                    .strokeColor: contrastingStroke(for: color(appearance.captionColor, hex: appearance.captionHex)),
                    .strokeWidth: -5, .paragraphStyle: paragraph]
        }
        let bounds = CGSize(width: 464, height: CGFloat.greatestFiniteMagnitude)
        func measure() -> CGSize {
            (caption as NSString).boundingRect(with: bounds, options: .usesLineFragmentOrigin, attributes: attributes(), context: nil).size
        }
        while pointSize > 16 && measure().height > 90 { pointSize -= 1 }
        let size = measure()
        let width = min(ceil(size.width) + 12, 512), height = ceil(size.height) + 8
        let center = captionCenter(appearance)
        let rect = CGRect(x: min(max(center.x - width / 2, 0), 512 - width),
                          y: min(max(center.y - height / 2, 0), 512 - height), width: width, height: height)
        return (attributes(), rect)
    }

    private static func addOutline(_ image: UIImage, width: Double, color: UIColor) -> UIImage {
        guard width > 0, let source = CIImage(image: image) else { return image }
        let expanded = source.applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": width])
        let solid = CIImage(color: CIColor(color: color)).cropped(to: source.extent)
        let clear = CIImage(color: CIColor.clear).cropped(to: source.extent)
        let silhouette = solid.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: expanded
        ])
        let result = source.composited(over: silhouette).cropped(to: source.extent)
        guard let output = renderContext.createCGImage(result, from: source.extent) else { return image }
        return UIImage(cgImage: output)
    }

    static func sample(_ emoji: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
            (emoji as NSString).draw(at: CGPoint(x: 40, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 380)])
        }
    }
}
