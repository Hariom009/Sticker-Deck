import UIKit

/// Splits one image holding many stickers (a creator's sticker sheet) into separate transparent stickers.
///
/// Works on an alpha mask: either the image's own transparency, a Vision cutout, or `keyedBackground` for
/// sheets on a plain background. Pieces are the mask's connected regions after a small dilation, so a
/// sticker's detached bits (letters of a word, a speech bubble) stay together while stickers with a clear
/// gap between them come apart.
enum StickerSheetSplitter {
    /// Gap (fraction of the longer side) closed when grouping parts into one sticker.
    // ponytail: one global gap; tight sheets merge neighbours, loose stickers split. Expose per-sheet if users hit either.
    nonisolated static let mergeDistance = 0.012
    /// Regions smaller than this share of the largest region are dropped as specks.
    nonisolated static let minimumShare = 0.02
    nonisolated static let limit = 40

    /// Separate stickers in reading order (rows top to bottom, left to right within a row).
    nonisolated static func split(_ image: UIImage) -> [UIImage] {
        guard let pixels = Pixels(image) else { return [] }
        let width = pixels.width, height = pixels.height
        // Label on a coarse grid: fast, and each cell is a max-pool of its pixels.
        let cell = max(1, Int((Double(max(width, height)) / 400).rounded(.up)))
        let gridWidth = (width + cell - 1) / cell, gridHeight = (height + cell - 1) / cell
        var grid = [Bool](repeating: false, count: gridWidth * gridHeight)
        pixels.data.withUnsafeBufferPointer { data in
            for y in 0..<height {
                let row = (y / cell) * gridWidth
                for x in 0..<width where data[(y * width + x) * 4 + 3] > 40 { grid[row + x / cell] = true }
            }
        }
        let radius = max(1, Int((Double(max(gridWidth, gridHeight)) * mergeDistance).rounded()))
        let joined = dilate(grid, width: gridWidth, height: gridHeight, radius: radius)
        let (labels, count) = label(joined, width: gridWidth, height: gridHeight)
        guard count > 0 else { return [] }

        // Pixel-accurate bounds and area per region.
        var minX = [Int](repeating: .max, count: count), minY = minX
        var maxX = [Int](repeating: -1, count: count), maxY = maxX
        var area = [Int](repeating: 0, count: count)
        pixels.data.withUnsafeBufferPointer { data in
            for y in 0..<height {
                let row = (y / cell) * gridWidth
                for x in 0..<width where data[(y * width + x) * 4 + 3] > 8 {
                    let region = Int(labels[row + x / cell])
                    guard region >= 0 else { continue }
                    area[region] += 1
                    minX[region] = min(minX[region], x); maxX[region] = max(maxX[region], x)
                    minY[region] = min(minY[region], y); maxY[region] = max(maxY[region], y)
                }
            }
        }
        let largest = area.max() ?? 0
        var kept = (0..<count).filter { area[$0] > 0 && Double(area[$0]) >= Double(largest) * minimumShare }
        if kept.count > limit { kept = Array(kept.sorted { area[$0] > area[$1] }.prefix(limit)) }

        // Reading order: a region joins the current row while its middle sits above that row's first bottom edge.
        kept.sort { minY[$0] + maxY[$0] < minY[$1] + maxY[$1] }
        var rows: [[Int]] = []
        var rowBottom = -1
        for region in kept {
            if rows.isEmpty || (minY[region] + maxY[region]) / 2 > rowBottom { rows.append([region]); rowBottom = maxY[region] }
            else { rows[rows.count - 1].append(region) }
        }
        let ordered = rows.flatMap { $0.sorted { minX[$0] < minX[$1] } }

        return ordered.compactMap { region in
            let rect = (x: minX[region], y: minY[region], width: maxX[region] - minX[region] + 1, height: maxY[region] - minY[region] + 1)
            var piece = [UInt8](repeating: 0, count: rect.width * rect.height * 4)
            pixels.data.withUnsafeBufferPointer { data in
                for y in 0..<rect.height {
                    let sourceY = rect.y + y, row = (sourceY / cell) * gridWidth
                    for x in 0..<rect.width {
                        let sourceX = rect.x + x
                        guard Int(labels[row + sourceX / cell]) == region else { continue }
                        let from = (sourceY * width + sourceX) * 4, to = (y * rect.width + x) * 4
                        piece[to] = data[from]; piece[to + 1] = data[from + 1]; piece[to + 2] = data[from + 2]; piece[to + 3] = data[from + 3]
                    }
                }
            }
            return Pixels(width: rect.width, height: rect.height, data: piece).image()
        }
    }

    /// Transparency for a sheet on a plain background: pixels close to the border color become clear, and
    /// background-colored areas fully enclosed by a sticker (white eyes on a white sheet) stay opaque.
    /// Nil when the border isn't a near-uniform color, i.e. this isn't a plain-background sheet.
    nonisolated static func keyedBackground(_ image: UIImage) -> UIImage? {
        guard var pixels = Pixels(image) else { return nil }
        let width = pixels.width, height = pixels.height
        guard width > 8, height > 8 else { return nil }
        var border: [(Int, Int, Int)] = []
        for x in stride(from: 0, to: width, by: 2) { for y in [0, 1, height - 2, height - 1] { border.append(pixels.rgb(x, y)) } }
        for y in stride(from: 0, to: height, by: 2) { for x in [0, 1, width - 2, width - 1] { border.append(pixels.rgb(x, y)) } }
        func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
        let background = (median(border.map { $0.0 }), median(border.map { $0.1 }), median(border.map { $0.2 }))
        func distance(_ color: (Int, Int, Int)) -> Int {
            max(abs(color.0 - background.0), abs(color.1 - background.1), abs(color.2 - background.2))
        }
        let uniform = border.filter { distance($0) <= 24 }.count
        guard Double(uniform) >= Double(border.count) * 0.85 else { return nil }

        let count = width * height
        var alpha = [UInt8](repeating: 0, count: count)
        pixels.data.withUnsafeBufferPointer { data in
            for index in 0..<count {
                let d = distance((Int(data[index * 4]), Int(data[index * 4 + 1]), Int(data[index * 4 + 2])))
                alpha[index] = d <= 16 ? 0 : d >= 48 ? 255 : UInt8((d - 16) * 255 / 32)
            }
        }
        // Flood the background in from the edges; clear pixels it can't reach are holes inside a sticker.
        var outside = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        for x in 0..<width { stack.append(x); stack.append((height - 1) * width + x) }
        for y in 0..<height { stack.append(y * width); stack.append(y * width + width - 1) }
        while let index = stack.popLast() {
            guard !outside[index], alpha[index] < 128 else { continue }
            outside[index] = true
            let x = index % width
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if index >= width { stack.append(index - width) }
            if index < count - width { stack.append(index + width) }
        }
        pixels.data.withUnsafeMutableBufferPointer { data in
            for index in 0..<count {
                let a = !outside[index] && alpha[index] < 128 ? 255 : Int(alpha[index])
                data[index * 4 + 3] = UInt8(a)
                // Buffer is premultiplied.
                for channel in 0..<3 { data[index * 4 + channel] = UInt8(Int(data[index * 4 + channel]) * a / 255) }
            }
        }
        return pixels.image()
    }

    private nonisolated static func dilate(_ grid: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        var horizontal = [Bool](repeating: false, count: grid.count)
        for y in 0..<height {
            for x in 0..<width where grid[y * width + x] {
                for nx in max(0, x - radius)...min(width - 1, x + radius) { horizontal[y * width + nx] = true }
            }
        }
        var result = [Bool](repeating: false, count: grid.count)
        for y in 0..<height {
            for x in 0..<width where horizontal[y * width + x] {
                for ny in max(0, y - radius)...min(height - 1, y + radius) { result[ny * width + x] = true }
            }
        }
        return result
    }

    /// 8-connected regions; -1 for empty cells.
    private nonisolated static func label(_ grid: [Bool], width: Int, height: Int) -> (labels: [Int32], count: Int) {
        var labels = [Int32](repeating: -1, count: grid.count)
        var count: Int32 = 0
        var stack: [Int] = []
        for start in grid.indices where grid[start] && labels[start] < 0 {
            labels[start] = count
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % width, y = index / width
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let next = ny * width + nx
                        if grid[next] && labels[next] < 0 { labels[next] = count; stack.append(next) }
                    }
                }
            }
            count += 1
        }
        return (labels, Int(count))
    }
}

/// Premultiplied RGBA8, row 0 at the top.
private nonisolated struct Pixels {
    let width: Int
    let height: Int
    var data: [UInt8]

    init(width: Int, height: Int, data: [UInt8]) {
        self.width = width; self.height = height; self.data = data
    }

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        width = cgImage.width; height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                                          bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        guard drawn else { return nil }
        self.data = data
    }

    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let index = (y * width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    /// The context owns its memory: an image made from a context over a Swift array could outlive that array.
    func image() -> UIImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let target = context.data else { return nil }
        let stride = context.bytesPerRow
        data.withUnsafeBytes { source in
            for row in 0..<height {
                (target + row * stride).copyMemory(from: source.baseAddress! + row * width * 4, byteCount: width * 4)
            }
        }
        return context.makeImage().map { UIImage(cgImage: $0) }
    }
}
