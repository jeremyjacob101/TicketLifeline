import SwiftUI

/// Native QR artwork: the saved matrix remains a real 2D code in the other mode,
/// while this lightweight Canvas view turns it into a cherry-blossom garden.
struct CodeArtView: View {
    let code: SavedCode

    var body: some View {
        if code.isBarcode {
            BarcodeSkylineCanvas(payload: code.payload)
        } else {
            CherryBlossomTreeCanvas(matrix: QRModuleMatrix(code: code))
        }
    }
}

private struct QRModuleMatrix {
    let side: Int
    private let values: [Bool]

    init(code: SavedCode) {
        if let encoded = code.visualMatrix,
           let sourceSide = code.visualSize,
            sourceSide > 0,
           encoded.count == sourceSide * sourceSide {
            let source = encoded.map { $0 == "1" }
            let displaySide = min(sourceSide, 41)
            side = displaySide
            values = (0..<(displaySide * displaySide)).map { index in
                let row = index / displaySide
                let column = index % displaySide
                return source[(row * sourceSide / displaySide) * sourceSide + (column * sourceSide / displaySide)]
            }
        } else {
            side = 29
            values = Self.fallback(payload: code.payload, side: side)
        }
    }

    func isDark(row: Int, column: Int) -> Bool { values[row * side + column] }

    private static func fallback(payload: String, side: Int) -> [Bool] {
        let seed = payload.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        var values = Array(repeating: false, count: side * side)
        for row in 0..<side {
            for column in 0..<side {
                let value = UInt64((row + 1) * 7_919 ^ (column + 1) * 10_007) &+ seed
                values[row * side + column] = value % 7 < 3
            }
        }
        for origin in [(0, 0), (side - 7, 0), (0, side - 7)] {
            for row in 0..<7 {
                for column in 0..<7 {
                    let edge = row == 0 || row == 6 || column == 0 || column == 6
                    let center = (2...4).contains(row) && (2...4).contains(column)
                    values[(origin.1 + row) * side + origin.0 + column] = edge || center
                }
            }
        }
        return values
    }
}

private struct CherryBlossomTreeCanvas: View {
    let matrix: QRModuleMatrix

    var body: some View {
        Canvas { context, size in
            let side = CGFloat(matrix.side)
            let module = min(size.width / (side * 1.42), size.height / (side * 0.94))
            let center = CGPoint(x: size.width / 2, y: size.height * 0.84)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.84, green: 0.91, blue: 0.96), Color(red: 0.96, green: 0.94, blue: 0.86)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            let canopyRadius = side * 0.46
            let trunkRadius: CGFloat = 2.5
            let trunkLayers = 12
            let maxCanopyLayers = 12
            var cubes: [TreeCube] = []
            for row in 0..<matrix.side {
                for column in 0..<matrix.side {
                    let dx = CGFloat(column) - side / 2
                    let dy = CGFloat(row) - side / 2
                    let distance = hypot(dx, dy)
                    let dark = matrix.isDark(row: row, column: column)
                    let ground: TreeBlock = !dark ? .dirt : distance < trunkRadius ? .trunk : distance >= canopyRadius ? .grass : .fallenPetal
                    cubes.append(TreeCube(row: row, column: column, level: 0, block: ground))

                    if dark && distance < trunkRadius {
                        for level in 1..<trunkLayers {
                            cubes.append(TreeCube(row: row, column: column, level: level, block: .trunk))
                        }
                    }
                    if dark && distance < canopyRadius {
                        let t = 1 - distance / canopyRadius
                        let layers = max(3, Int((CGFloat(maxCanopyLayers) * (0.25 + 0.75 * t * t)).rounded()))
                        let domeOffset = Int((t * 3).rounded(.down))
                        for level in 0..<layers {
                            cubes.append(TreeCube(row: row, column: column, level: trunkLayers + domeOffset + level, block: .blossom))
                        }
                    }
                }
            }
            cubes.sort { ($0.row + $0.column, $0.level) < ($1.row + $1.column, $1.level) }
            for cube in cubes {
                let point = CGPoint(
                    x: center.x + (CGFloat(cube.column) - CGFloat(cube.row)) * module * 0.5,
                    y: center.y + (CGFloat(cube.column) + CGFloat(cube.row) - side) * module * 0.24 - CGFloat(cube.level) * module * 0.74
                )
                drawCube(context: &context, point: point, module: module, block: cube.block)
            }
            context.draw(Text("Cherry blossom QR garden").font(.caption.weight(.medium)).foregroundColor(.black.opacity(0.55)), at: CGPoint(x: size.width / 2, y: size.height - 15))
        }
        .accessibilityLabel("Cherry blossom tree interpretation of this QR code")
    }

    private func drawCube(context: inout GraphicsContext, point: CGPoint, module: CGFloat, block: TreeBlock) {
        let half = module * 0.5
        let depth = module * 0.26
        let top = CGPoint(x: point.x, y: point.y - module * 0.74)
        let topFace = polygon([top, CGPoint(x: top.x + half, y: top.y + depth), CGPoint(x: top.x, y: top.y + depth * 2), CGPoint(x: top.x - half, y: top.y + depth)])
        let leftFace = polygon([CGPoint(x: top.x - half, y: top.y + depth), CGPoint(x: top.x, y: top.y + depth * 2), CGPoint(x: point.x, y: point.y + depth * 2), CGPoint(x: point.x - half, y: point.y + depth)])
        let rightFace = polygon([CGPoint(x: top.x + half, y: top.y + depth), CGPoint(x: top.x, y: top.y + depth * 2), CGPoint(x: point.x, y: point.y + depth * 2), CGPoint(x: point.x + half, y: point.y + depth)])
        context.fill(leftFace, with: .color(block.top.opacity(0.75)))
        context.fill(rightFace, with: .color(block.top.opacity(0.55)))
        context.fill(topFace, with: .color(block.top))
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

private struct TreeCube {
    let row: Int
    let column: Int
    let level: Int
    let block: TreeBlock
}

private enum TreeBlock {
    case dirt, grass, trunk, blossom, fallenPetal

    var top: Color {
        switch self {
        case .dirt: Color(red: 0.79, green: 0.65, blue: 0.43)
        case .grass: Color(red: 0.32, green: 0.62, blue: 0.30)
        case .trunk: Color(red: 0.45, green: 0.25, blue: 0.13)
        case .blossom: Color(red: 0.98, green: 0.57, blue: 0.72)
        case .fallenPetal: Color(red: 0.96, green: 0.66, blue: 0.76)
        }
    }
}

private struct BarcodeSkylineCanvas: View {
    let payload: String

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.05, green: 0.10, blue: 0.20), Color(red: 0.27, green: 0.16, blue: 0.31)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            let horizon = size.height * 0.78
            var x: CGFloat = 24
            let bytes: [UInt8] = payload.utf8.isEmpty ? [0] : Array(payload.utf8)
            for index in 0..<min(bytes.count * 2, 48) {
                let byte = bytes[index % bytes.count]
                let width = CGFloat(4 + Int(byte % 6))
                let height = CGFloat(48 + Int((byte &+ UInt8((index * 13) % 256)) % 124))
                let front = CGRect(x: x, y: horizon - height, width: width, height: height)
                context.fill(Path(front), with: .color(Color(red: 0.17, green: 0.34, blue: 0.50)))
                var roof = Path()
                roof.move(to: CGPoint(x: front.minX, y: front.minY))
                roof.addLine(to: CGPoint(x: front.minX + 8, y: front.minY - 7))
                roof.addLine(to: CGPoint(x: front.maxX + 8, y: front.minY - 7))
                roof.addLine(to: CGPoint(x: front.maxX, y: front.minY))
                roof.closeSubpath()
                context.fill(roof, with: .color(Color(red: 0.38, green: 0.66, blue: 0.78)))
                if width >= 7 {
                    for y in stride(from: front.minY + 9, to: front.maxY - 5, by: 15) {
                        context.fill(Path(CGRect(x: front.minX + 2, y: y, width: width - 4, height: 3)), with: .color(Color(red: 0.98, green: 0.82, blue: 0.40).opacity(0.85)))
                    }
                }
                x += width + 3
                if x > size.width - 26 { break }
            }
            context.draw(Text("Barcode skyline").font(.caption.weight(.medium)).foregroundColor(.white.opacity(0.75)), at: CGPoint(x: size.width / 2, y: size.height - 15))
        }
        .accessibilityLabel("Skyline interpretation of this barcode")
    }
}
