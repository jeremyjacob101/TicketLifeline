import CoreImage
import MetalKit
import SwiftUI

struct QRTreeMetalView: UIViewRepresentable {
    let code: SavedCode
    let isFlat: Bool

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
        if let renderer = QRTreeMetalRenderer(view: view, matrix: QRTreeMatrix(code: code), initiallyFlat: isFlat) {
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
        if let encoded = code.visualMatrix,
           let size = code.visualSize,
           encoded.count == size * size,
           size > 0 {
            side = size
            values = encoded.map { $0 == "1" }
        } else if let generated = Self.generate(payload: code.payload) {
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
        let heightScale = blockSize / 7.5
        let trunkRadius = max(1.8, Float(side) * 0.07)
        let canopyRadius = Float(side) * 0.47
        var blocks: [GPUBlock] = []
        func add(_ column: Int, _ row: Int, base: Float, height: Float, type: UInt32) {
            blocks.append(GPUBlock(position: SIMD4(Float(column), Float(row), 0, 0), height: height, baseY: base, type: type))
        }
        for row in 0..<side {
            for column in 0..<side {
                let dark = matrix.dark(row, column)
                let distance = hypot(Float(column) - center, Float(row) - center)
                let type: UInt32 = !dark ? 0 : distance < trunkRadius ? 2 : distance >= canopyRadius ? 3 : 4
                add(column, row, base: 0, height: blockSize, type: type)
            }
        }
        // Two short, camera-facing root columns sit below the crown. They
        // make the trunk read as a real tree without placing any brown block
        // above the leaves or relying on a depth bias.
        let core = Int(center.rounded(.down))
        let frontRow = max(0, core - 1)
        for column in core...min(side - 1, core + 1) {
            let height = (26 + pseudoRandom(column, frontRow, 89) * 4) * heightScale
            add(column, frontRow, base: blockSize, height: height, type: 6)
        }
        for row in 0..<side {
            for column in 0..<side {
                let dark = matrix.dark(row, column)
                let distance = hypot(Float(column) - center, Float(row) - center)
                let ornamentalRadius = Float(side) * 0.43
                let ornamentalFullness = max(0, 1 - distance / ornamentalRadius)
                let ornamental = !dark && distance < ornamentalRadius && pseudoRandom(column, row, 61) > 0.88 - ornamentalFullness * 0.22
                if !dark && !ornamental { continue }

                if dark && distance < trunkRadius {
                    // A mature trunk reaches into the lower crown; depth
                    // testing still keeps the foliage in front of it.
                    let height = (60 + pseudoRandom(column, row, 10) * 8) * heightScale
                    add(column, row, base: blockSize, height: height, type: 2)
                    // A blossom cap is actual occluding geometry—not alpha—so
                    // the trunk supports the crown without poking through it.
                    let capBase = (61 + pseudoRandom(column, row, 27) * 5) * heightScale
                    let capHeight = (18 + pseudoRandom(column, row, 31) * 8) * heightScale
                    add(column, row, base: capBase, height: capHeight, type: 1)
                    continue
                }
                if distance < canopyRadius {
                    let fullness = 1 - distance / canopyRadius
                    // A narrow opening on the camera-facing side lets the
                    // trunk emerge below the crown. This is real geometry,
                    // not a depth/opacity override, so leaves still conceal
                    // the upper trunk naturally.
                    let frontTrunkWindow = distance < trunkRadius * 1.35 && Float(row + column) < center * 2 - 0.5
                    if frontTrunkWindow { continue }
                    if !ornamental && fullness < 0.24 && pseudoRandom(column, row, 29) < 0.34 { continue }
                    let base = (34 + fullness * 25 + pseudoRandom(column, row, 7) * 10) * heightScale
                    let height = (7 + fullness * 31 + pseudoRandom(column, row, ornamental ? 43 : 11) * 11) * heightScale
                    add(column, row, base: base, height: height, type: ornamental ? 5 : 1)
                } else if dark && pseudoRandom(column, row, 13) > 0.36 {
                    let height = (4 + pseudoRandom(column, row, 17) * 5) * heightScale
                    add(column, row, base: blockSize, height: height, type: 3)
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
