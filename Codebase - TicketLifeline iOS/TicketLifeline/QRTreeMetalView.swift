import CoreImage
import MetalKit
import SwiftUI

struct QRTreeMetalView: UIViewRepresentable {
    let isFlat: Bool
    private let matrix: QRTreeMatrix

    init(code: SavedCode, isFlat: Bool) {
        self.isFlat = isFlat
        matrix = QRTreeMatrix(code: code)
    }

    init(code: DetectedCode, isFlat: Bool) {
        self.isFlat = isFlat
        matrix = QRTreeMatrix(code: code)
    }

    final class Coordinator {
        fileprivate var renderer: QRTreeMetalRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        view.backgroundColor = UIColor(white: 0.969, alpha: 1)
        if let renderer = QRTreeMetalRenderer(view: view, matrix: matrix, initiallyFlat: isFlat) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.setFlat(isFlat)
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.renderer = nil
    }
}

private struct QRTreeMatrix {
    let side: Int
    let values: [Bool]

    init(code: SavedCode) {
        self.init(
            encoded: code.visualMatrix,
            width: code.visualWidth ?? code.visualSize,
            height: code.visualHeight ?? code.visualSize,
            payload: code.payload
        )
    }

    init(code: DetectedCode) {
        self.init(
            encoded: code.visualMatrix,
            width: code.visualWidth,
            height: code.visualHeight,
            payload: code.payload
        )
    }

    private init(encoded: String?, width: Int?, height: Int?, payload: String) {
        if let encoded,
           let width,
           let height,
           width == height,
           encoded.count == width * height,
           width > 0 {
            side = width
            values = encoded.map { $0 == "1" }
        } else if let generated = Self.generate(payload: payload) {
            side = generated.side
            values = generated.values
        } else {
            side = 21
            values = Array(repeating: false, count: 21 * 21)
        }
    }

    func dark(_ row: Int, _ column: Int) -> Bool { values[row * side + column] }

    private static func generate(payload: String) -> (side: Int, values: [Bool])? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        let side = Int(image.extent.width)
        var pixels = Array(repeating: UInt8(0), count: side * side * 4)
        CIContext().render(image, toBitmap: &pixels, rowBytes: side * 4, bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (side, (0..<(side * side)).map { pixels[$0 * 4] < 128 })
    }
}

private struct GPUBlock {
    var position: SIMD4<Float>
    var height: Float
    var baseY: Float
    var type: UInt32
    var padding: UInt32 = 0
}

private struct GPUUniforms {
    var aspectRatio: Float
    var time: Float
    var blockCount: Float
    var progress: Float
    var gridSize: Float
    var moduleScale: Float
    var padding = SIMD2<Float>(repeating: 0)
}

struct QRTreeCanopyColumn {
    let baseModules: Float
    let heightModules: Float

    var topModules: Float { baseModules + heightModules }
}

/// Matrix-relative dimensions keep the tree silhouette stable for every QR
/// version instead of making larger matrices produce progressively flatter
/// trees. Values are expressed in QR-module units and converted to Metal world
/// units only when the GPU blocks are created.
struct QRTreeShapeProfile {
    let side: Float

    init(side: Int) {
        self.side = max(1, Float(side))
    }

    var canopyRadius: Float { side * 0.47 }
    var ornamentalRadius: Float { side * 0.445 }
    var leafWidthModules: Float { 0.74 }
    var trunkWidthModules: Float { max(1.25, side * 0.055) }
    var trunkHeightModules: Float { side * 0.50 }

    func normalizedRadius(for distance: Float) -> Float {
        min(max(distance / canopyRadius, 0), 1)
    }

    func domeAmount(at distance: Float) -> Float {
        let radius = normalizedRadius(for: distance)
        return max(0, 1 - radius * radius)
    }

    func ornamentalProbability(at distance: Float) -> Float {
        0.30 + domeAmount(at: distance) * 0.30
    }

    func edgeRetention(at distance: Float) -> Float {
        let radius = normalizedRadius(for: distance)
        let interiorAmount = min(max((1 - radius) / 0.18, 0), 1)
        return 0.22 + interiorAmount * 0.78
    }

    func canopyColumn(
        at distance: Float,
        baseNoise: Float,
        topNoise: Float
    ) -> QRTreeCanopyColumn {
        let dome = domeAmount(at: distance)
        let clampedBaseNoise = min(max(baseNoise, 0), 1)
        let clampedTopNoise = min(max(topNoise, 0), 1)

        // Move short leaf blocks along the dome instead of stretching every
        // leaf from the canopy underside to its top. This preserves the round
        // silhouette without the long vertical curtains visible at the rim.
        let base = side * (0.23 + dome * 0.255)
            + (clampedBaseNoise - 0.5) * side * 0.02
        let height = side * (0.044 + dome * 0.036)
            + clampedTopNoise * side * 0.012
        return QRTreeCanopyColumn(
            baseModules: base,
            heightModules: max(side * 0.04, height)
        )
    }
}

private final class QRTreeMetalRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let blocksPipeline: MTLRenderPipelineState
    private let skyPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private let blocksBuffer: MTLBuffer
    private let uniformBuffer: MTLBuffer
    private let blockCount: Int
    private let gridSize: Float
    private let startTime = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime()
    private var rawProgress: Float
    private var targetProgress: Float

    init?(view: MTKView, matrix: QRTreeMatrix, initiallyFlat: Bool) {
        guard let device = view.device,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let blockVertex = library.makeFunction(name: "qrBlockVertex"),
              let blockFragment = library.makeFunction(name: "qrBlockFragment"),
              let skyVertex = library.makeFunction(name: "qrSkyVertex"),
              let skyFragment = library.makeFunction(name: "qrSkyFragment"),
              let shadowVertex = library.makeFunction(name: "qrShadowVertex"),
              let shadowFragment = library.makeFunction(name: "qrShadowFragment") else { return nil }

        func pipeline(vertex: MTLFunction, fragment: MTLFunction, blending: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            if blending {
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        do {
            blocksPipeline = try pipeline(vertex: blockVertex, fragment: blockFragment)
            skyPipeline = try pipeline(vertex: skyVertex, fragment: skyFragment)
            shadowPipeline = try pipeline(vertex: shadowVertex, fragment: shadowFragment, blending: true)
        } catch { return nil }

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState
        let overlay = MTLDepthStencilDescriptor()
        overlay.depthCompareFunction = .always
        overlay.isDepthWriteEnabled = false
        guard let overlayDepthState = device.makeDepthStencilState(descriptor: overlay) else { return nil }
        self.overlayDepthState = overlayDepthState

        let blocks = Self.generateBlocks(matrix)
        guard let blocksBuffer = device.makeBuffer(bytes: blocks, length: max(1, blocks.count * MemoryLayout<GPUBlock>.stride), options: .storageModeShared),
              let uniformBuffer = device.makeBuffer(length: MemoryLayout<GPUUniforms>.stride, options: .storageModeShared) else { return nil }
        self.blocksBuffer = blocksBuffer
        self.uniformBuffer = uniformBuffer
        blockCount = blocks.count
        gridSize = Float(matrix.side)
        rawProgress = initiallyFlat ? 1 : 0
        targetProgress = rawProgress
        self.queue = queue
        super.init()
    }

    func setFlat(_ flat: Bool) { targetProgress = flat ? 1 : 0 }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastTime, 0.05))
        lastTime = now
        rawProgress += (targetProgress - rawProgress) * min(1, 4 * delta)
        if abs(rawProgress - targetProgress) < 0.001 { rawProgress = targetProgress }
        let progress = rawProgress < 0.5 ? 4 * rawProgress * rawProgress * rawProgress : 1 - pow(-2 * rawProgress + 2, 3) / 2
        var uniforms = GPUUniforms(
            aspectRatio: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            time: Float(now - startTime),
            blockCount: Float(blockCount),
            progress: progress,
            gridSize: gridSize,
            moduleScale: 29 / gridSize
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<GPUUniforms>.stride)

        encoder.setDepthStencilState(overlayDepthState)
        encoder.setRenderPipelineState(skyPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        encoder.setDepthStencilState(depthState)
        encoder.setRenderPipelineState(blocksPipeline)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(blocksBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: blockCount)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private static func generateBlocks(_ matrix: QRTreeMatrix) -> [GPUBlock] {
        let side = matrix.side
        let center = Float(side - 1) / 2
        let blockSize: Float = 0.0245
        let profile = QRTreeShapeProfile(side: side)
        var blocks: [GPUBlock] = []
        func add(
            _ column: Float,
            _ row: Float,
            baseModules: Float,
            heightModules: Float,
            type: UInt32,
            widthModules: Float = 1
        ) {
            blocks.append(
                GPUBlock(
                    position: SIMD4(column, row, widthModules, 0),
                    height: heightModules * blockSize,
                    baseY: baseModules * blockSize,
                    type: type
                )
            )
        }

        // The complete ground matrix is never altered by the decorative tree,
        // preserving the exact flat QR endpoint for scanning.
        for row in 0..<side {
            for column in 0..<side {
                let dark = matrix.dark(row, column)
                let distance = hypot(Float(column) - center, Float(row) - center)
                let trunkFootprint = profile.trunkWidthModules * 0.5
                let type: UInt32
                if !dark {
                    type = 0
                } else if distance < trunkFootprint {
                    type = 2
                } else if distance >= profile.canopyRadius {
                    type = 3
                } else {
                    type = 4
                }
                add(
                    Float(column),
                    Float(row),
                    baseModules: 0,
                    heightModules: 1,
                    type: type
                )
            }
        }

        // One continuous, matrix-independent trunk works even when the QR's
        // center modules are light. It is decorative (type 6), so it contracts
        // completely out of the scannable flat view.
        add(
            center,
            center,
            baseModules: 1,
            heightModules: profile.trunkHeightModules,
            type: 6,
            widthModules: profile.trunkWidthModules
        )

        for row in 0..<side {
            for column in 0..<side {
                let dark = matrix.dark(row, column)
                let distance = hypot(Float(column) - center, Float(row) - center)
                if distance < profile.canopyRadius {
                    let coversTrunk = distance < profile.trunkWidthModules * 0.9
                    let ornamental = !dark
                        && distance < profile.ornamentalRadius
                        && (
                            coversTrunk
                                || pseudoRandom(column, row, 61)
                                    < profile.ornamentalProbability(at: distance)
                        )
                    guard dark || ornamental else { continue }

                    // Thin only the outside rim. This keeps an organic edge
                    // while guaranteeing a dense center that fully caps the
                    // trunk instead of cutting a sight line through the crown.
                    if !coversTrunk,
                       pseudoRandom(column, row, 29) > profile.edgeRetention(at: distance) {
                        continue
                    }

                    let columnShape = profile.canopyColumn(
                        at: distance,
                        baseNoise: pseudoRandom(column, row, 7),
                        topNoise: pseudoRandom(column, row, ornamental ? 43 : 11)
                    )
                    add(
                        Float(column),
                        Float(row),
                        baseModules: columnShape.baseModules,
                        heightModules: columnShape.heightModules,
                        type: ornamental ? 5 : 1,
                        widthModules: profile.leafWidthModules
                    )
                } else if dark, pseudoRandom(column, row, 13) > 0.36 {
                    add(
                        Float(column),
                        Float(row),
                        baseModules: 1,
                        heightModules: 0.55 + pseudoRandom(column, row, 17) * 0.65,
                        type: 3
                    )
                }
            }
        }
        return blocks
    }

    private static func pseudoRandom(_ column: Int, _ row: Int, _ seed: Int) -> Float {
        let value = sin(Float(column + 1) * 91.73 + Float(row + 1) * 57.31 + Float(seed) * 19.19) * 10000
        return value - floor(value)
    }
}
