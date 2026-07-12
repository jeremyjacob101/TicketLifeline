import SwiftUI

/// Keeps the real Code 128 image available in scan mode and transforms the
/// same barcode rhythm into a centered, animated city scene.
struct BarcodeCityView: View {
    let code: SavedCode
    let isFlat: Bool
    @State private var progress: CGFloat

    init(code: SavedCode, isFlat: Bool) {
        self.code = code
        self.isFlat = isFlat
        _progress = State(initialValue: isFlat ? 0 : 1)
    }

    var body: some View {
        ZStack {
            BarcodeCityStage(payload: code.payload, progress: progress)

            BarcodeImage(payload: code.payload)
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                .opacity(1 - Double(smoothstep(0.08, 0.38, progress)))
                .scaleEffect(1 - progress * 0.035)
                .accessibilityHidden(progress > 0.5)
        }
        .onAppear { setMode(animated: false) }
        .onChange(of: isFlat) { _, _ in setMode(animated: true) }
        .accessibilityLabel(isFlat ? "Scannable barcode" : "Skyline interpretation of this barcode")
    }

    private func setMode(animated: Bool) {
        let target: CGFloat = isFlat ? 0 : 1
        if animated {
            withAnimation(.easeInOut(duration: 0.58)) { progress = target }
        } else {
            progress = target
        }
    }

    private func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }
}

private struct BarcodeCityStage: View {
    let payload: String
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            let sky = Gradient(colors: [
                mix(Color.white, Color(red: 0.969, green: 0.984, blue: 1), progress),
                mix(Color(red: 0.973, green: 0.980, blue: 0.988), Color(red: 0.855, green: 0.889, blue: 0.875), progress)
            ])
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            let cityAlpha = smoothstep(0.02, 0.22, progress)
            guard cityAlpha > 0 else { return }
            drawCity(context: &context, size: size, alpha: cityAlpha)
        }
        .accessibilityHidden(true)
    }

    private func drawCity(context: inout GraphicsContext, size: CGSize, alpha: CGFloat) {
        let horizon = size.height * 0.61
        let roadTopLeft = CGPoint(x: size.width * 0.08, y: horizon + 28)
        let roadTopRight = CGPoint(x: size.width * 0.92, y: horizon + 28)
        context.fill(path([roadTopLeft, roadTopRight, CGPoint(x: size.width + 44, y: size.height), CGPoint(x: -44, y: size.height)]), with: .color(Color(red: 0.24, green: 0.28, blue: 0.34).opacity(Double(alpha))))
        context.fill(path([CGPoint(x: size.width * 0.11, y: horizon + 10), CGPoint(x: size.width * 0.89, y: horizon + 10), roadTopRight, roadTopLeft]), with: .color(Color(red: 0.78, green: 0.75, blue: 0.68).opacity(Double(alpha))))

        for index in 0..<7 {
            let x = size.width * (0.16 + CGFloat(index) * 0.11)
            context.stroke(Path { path in
                path.move(to: CGPoint(x: x, y: horizon + 54))
                path.addLine(to: CGPoint(x: x + 13, y: horizon + 72))
            }, with: .color(.white.opacity(Double(alpha * 0.58))), lineWidth: 2)
        }

        let runs = barcodeRuns()
        let total = CGFloat(max(1, runs.map(\.width).reduce(0, +)))
        let module = size.width * 0.78 / total
        var cursor = size.width * 0.11
        for run in runs {
            let width = max(3.4, CGFloat(run.width) * module * 1.12)
            let seed = random(run.index, run.width, 3)
            let depth = 7 + min(19, width * 1.35)
            let height = 54 + CGFloat(run.width) * 7 + seed * 62
            let normalized = (cursor + width * 0.5) / size.width
            let base = horizon + 12 + normalized * 12
            let top = max(28, base - height)
            let palette = palette(for: run.index)

            let front = CGRect(x: cursor, y: top, width: width, height: base - top)
            let side = path([
                CGPoint(x: front.maxX, y: front.minY),
                CGPoint(x: front.maxX + depth, y: front.minY - depth * 0.52),
                CGPoint(x: front.maxX + depth, y: front.maxY - depth * 0.52),
                CGPoint(x: front.maxX, y: front.maxY)
            ])
            let roof = path([
                CGPoint(x: front.minX, y: front.minY),
                CGPoint(x: front.maxX, y: front.minY),
                CGPoint(x: front.maxX + depth, y: front.minY - depth * 0.52),
                CGPoint(x: front.minX + depth, y: front.minY - depth * 0.52)
            ])
            let shadow = path([
                CGPoint(x: front.minX, y: base), CGPoint(x: front.maxX, y: base),
                CGPoint(x: front.maxX + depth * 2.1, y: base + 18), CGPoint(x: front.minX + depth * 0.8, y: base + 13)
            ])
            context.fill(shadow, with: .color(Color.black.opacity(Double(alpha * 0.16))))
            context.fill(side, with: .color(palette.side.opacity(Double(alpha))))
            context.fill(roof, with: .color(palette.roof.opacity(Double(alpha))))
            context.fill(Path(front), with: .color(palette.front.opacity(Double(alpha))))

            if width > 5.8 {
                let rows = max(2, Int((front.height - 12) / 15))
                for row in 0..<rows where random(run.index + row, row, 41) > 0.18 {
                    let y = front.minY + 9 + CGFloat(row) * 14
                    context.fill(Path(CGRect(x: front.minX + max(1.2, width * 0.2), y: y, width: max(1.2, width * 0.36), height: 2.2)), with: .color(palette.window.opacity(Double(alpha * 0.9))))
                }
            }
            if height > 108 && random(run.index, run.width, 71) > 0.62 {
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: front.midX + depth * 0.5, y: front.minY - depth * 0.25))
                    path.addLine(to: CGPoint(x: front.midX + depth * 0.62, y: front.minY - 12))
                }, with: .color(palette.side.opacity(Double(alpha))), lineWidth: 1.25)
            }
            cursor += CGFloat(run.width) * module
        }
    }

    private func barcodeRuns() -> [(index: Int, width: Int)] {
        let bytes = Array(payload.utf8)
        let source = bytes.isEmpty ? [UInt8(0xA5)] : bytes
        var runs: [(Int, Int)] = []
        for index in 0..<min(38, source.count * 2 + 10) {
            let byte = source[index % source.count]
            runs.append((index, 1 + Int((byte &+ UInt8((index * 17) % 255)) % 5)))
        }
        return runs
    }

    private func palette(for index: Int) -> (front: Color, side: Color, roof: Color, window: Color) {
        switch index % 4 {
        case 0: return (Color(red: 0.12, green: 0.16, blue: 0.22), Color(red: 0.22, green: 0.25, blue: 0.31), Color(red: 0.29, green: 0.33, blue: 0.39), Color(red: 0.98, green: 0.75, blue: 0.14))
        case 1: return (Color(red: 0.08, green: 0.31, blue: 0.39), Color(red: 0.14, green: 0.42, blue: 0.49), Color(red: 0.18, green: 0.53, blue: 0.60), Color(red: 0.66, green: 0.95, blue: 0.82))
        case 2: return (Color(red: 0.19, green: 0.18, blue: 0.51), Color(red: 0.26, green: 0.22, blue: 0.79), Color(red: 0.36, green: 0.33, blue: 0.84), Color(red: 0.77, green: 0.71, blue: 0.98))
        default: return (Color(red: 0.49, green: 0.18, blue: 0.07), Color(red: 0.60, green: 0.20, blue: 0.07), Color(red: 0.76, green: 0.25, blue: 0.05), Color(red: 1, green: 0.84, blue: 0.67))
        }
    }

    private func random(_ a: Int, _ b: Int, _ seed: Int) -> CGFloat {
        let value = sin(CGFloat(a + 1) * 31.7 + CGFloat(b + 1) * 47.1 + CGFloat(seed) * 13.3) * 10_000
        return value - floor(value)
    }

    private func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }

    private func mix(_ from: Color, _ to: Color, _ amount: CGFloat) -> Color {
        // Gradient endpoints are deliberately discrete system colors; opacity
        // handles the visual interpolation as the city rises.
        amount < 0.5 ? from : to
    }

    private func path(_ points: [CGPoint]) -> Path {
        var result = Path()
        guard let first = points.first else { return result }
        result.move(to: first)
        for point in points.dropFirst() { result.addLine(to: point) }
        result.closeSubpath()
        return result
    }
}
